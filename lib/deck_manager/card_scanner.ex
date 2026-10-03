defmodule DeckManager.CardScanner do
  @moduledoc """
  Reads Magic cards off a photo in reviewable steps.

  Every real Magic card prints its collector number and set code in the bottom-
  left corner. A vision model reads those two identifiers, and each one is
  confirmed against Scryfall's per-printing endpoint to recover the canonical
  name — so the CSV never depends on the model guessing a card's name, only on
  it reading the small print.

  The work is split so a human can check it at each stage, because the failure
  mode that matters isn't a misread digit, it's the model quietly reporting two
  cards for a photo holding fifteen:

    1. `count/2` — how many cards are in the photo. Run as several independent
       passes so disagreement is visible rather than silent.
    2. `read/3` — the set code and collector number for each card, told up front
       exactly how many to find.
    3. `resolve/1` — each row looked up on Scryfall, so the review shows real
       card names and unmatched rows stand out.
    4. `to_csv/1` — Moxfield import text from the reviewed rows.

  Foil is not asked of the model at all. Reading a rainbow sheen off a phone
  photo is guesswork, and the person holding the cards already knows.
  """

  alias DeckManager.{Anthropic, Image, Language, Moxfield, Scryfall, Video}

  # Counting passes are cheap next to the cost of finding out later that a photo
  # was half missed, so the default runs a few and shows the spread.
  @count_passes 3

  # Vision requests carry a full-resolution image and adaptive thinking, so they
  # need room; a truncated response is an unparseable one.
  @max_tokens 16_000

  # HEIC is here because that is what an iPhone AirDrops; `DeckManager.Image`
  # transcodes it on the way to the API.
  @image_extensions ~w(.jpg .jpeg .png .gif .webp .heic .heif)

  # Below this on the long edge, corner text on a card in a fanned stack is at
  # the edge of what any model can resolve. Worth saying out loud before a bad
  # scan rather than after it. The byte figure is the fallback heuristic for
  # when the pixel dimensions can't be read.
  @low_resolution_edge 2000
  @low_resolution_bytes 400_000

  @count_schema %{
    type: "object",
    properties: %{
      layout: %{
        type: "string",
        description:
          "One sentence describing how the cards are arranged (fanned stack, grid, single row, overlapping pile)."
      },
      cards: %{
        type: "array",
        description:
          "One entry per distinct physical card visible, in reading order: top to bottom, then left to right.",
        items: %{
          type: "object",
          properties: %{
            position: %{
              type: "integer",
              description: "1-based index in reading order."
            },
            description: %{
              type: "string",
              description:
                "A few words that identify this specific card's visible area — border colour, power/toughness, artist name, any readable words. Enough that a human could point at it."
            }
          },
          required: ["position", "description"],
          additionalProperties: false
        }
      }
    },
    required: ["layout", "cards"],
    additionalProperties: false
  }

  @count_prompt """
  This is a photograph of Magic: The Gathering cards. Your only job right now is
  to enumerate every distinct physical card that is at least partly visible.

  Cards in these photos are usually FANNED or STACKED with a large overlap, so
  most of them show only a thin horizontal strip: the bottom edge of the card,
  with its collector line (rarity letter, collector number, set code, language,
  artist name) and often the bottom of the text box or a power/toughness box.
  Each such strip is its own card. There are frequently ten or more.

  Rules:
  - Work down the photo one strip at a time and emit an entry for every strip,
    including the topmost card (which may be cut off by the frame edge) and the
    bottommost card (which is usually the only fully visible one).
  - A card counts even if its corner text is blurry or unreadable. You are
    counting cards, not reading them.
  - Do not merge two adjacent strips because they look alike — repeated printings
    of the same card are still separate cards and each gets its own entry.
  - Do not emit an entry for anything that is not a card (the table, a sleeve, a
    shadow, a hand).

  Return the layout description and the full list. The length of the list is the
  answer, so do not stop early.
  """

  @read_schema %{
    type: "object",
    properties: %{
      cards: %{
        type: "array",
        items: %{
          type: "object",
          properties: %{
            position: %{
              type: "integer",
              description: "1-based index in reading order, top to bottom."
            },
            set: %{
              type: "string",
              description:
                "The set code printed on the collector line (e.g. \"EOE\", \"HOB\", \"MH3\") — 3-4 letters or digits. Empty string if you genuinely cannot read it."
            },
            collector_number: %{
              type: "string",
              description:
                "The collector number printed on the same line (e.g. \"42\", \"0123\", \"112a\"). Leading zeros may be kept or dropped. Empty string if you genuinely cannot read it."
            },
            name: %{
              type: "string",
              description:
                "The card's name if visible, otherwise a short description of what you can see. Used only as a review label."
            }
          },
          required: ["position", "set", "collector_number", "name"],
          additionalProperties: false
        }
      }
    },
    required: ["cards"],
    additionalProperties: false
  }

  @doc """
  Count the cards in one image. Returns `{:ok, %{count: n, counts: [...],
  layout: text, cards: [%{position, description}]}}` or `{:error, reason}`.

  Runs `:passes` independent counts (default #{@count_passes}) and reports every
  result. `count` is the consensus — the most common answer, ties broken high —
  and `cards` are the descriptions from a pass that produced it. Counting works
  by enumerating each card, because a model asked for a number will guess one
  and a model asked for a list has to look.

  A pass that fails outright doesn't sink the count, but it is reported in
  `:failed` and `:error` rather than quietly narrowing the sample: a consensus
  of one surviving pass is a much weaker claim than a consensus of three, and
  the caller can only tell the difference if it is said.
  """
  def count(image_ref, opts \\ []) do
    {passes, opts} = Keyword.pop(opts, :passes, @count_passes)

    results =
      1..passes
      |> Task.async_stream(fn _ -> count_once(image_ref, opts) end,
        max_concurrency: passes,
        timeout: :infinity
      )
      |> Enum.map(fn {:ok, result} -> result end)

    case Enum.split_with(results, &match?({:ok, _}, &1)) do
      {[], [{:error, reason} | _]} ->
        {:error, reason}

      {oks, errors} ->
        found = Enum.map(oks, fn {:ok, found} -> found end)
        counts = Enum.map(found, &length(&1.cards))
        consensus = consensus(counts)
        best = Enum.find(found, &(length(&1.cards) == consensus))

        {:ok,
         %{
           count: consensus,
           counts: counts,
           requested: passes,
           failed: length(errors),
           error: first_error(errors),
           layout: best.layout,
           cards: best.cards
         }}
    end
  end

  defp first_error([{:error, reason} | _]), do: reason
  defp first_error([]), do: nil

  defp count_once(image_ref, opts) do
    with {:ok, text} <- ask(image_ref, @count_prompt, @count_schema, opts),
         {:ok, %{"cards" => cards} = map} <- decode(text) do
      {:ok, %{layout: map["layout"] || "", cards: Enum.map(cards, &describe/1)}}
    end
  end

  defp describe(card) do
    %{position: card["position"], description: card["description"] || ""}
  end

  # The most common answer, ties broken toward the larger — a pass that missed
  # cards is a far more common failure here than one that invented them.
  defp consensus(counts) do
    counts
    |> Enum.frequencies()
    |> Enum.max_by(fn {count, freq} -> {freq, count} end)
    |> elem(0)
  end

  @doc """
  Read the set code and collector number for each card in one image, given the
  confirmed `count`. Returns `{:ok, rows}` or `{:error, reason}`, where each row
  is `%{position, set, collector_number, name, foil: false}`.

  The count is stated in the prompt and enforced on the response: a model told
  to find exactly fifteen cards looks for fifteen, and a reply of the wrong
  length is retried once before being returned as-is for the human to fix.
  """
  def read(image_ref, count, opts \\ []) do
    case read_once(image_ref, count, opts) do
      {:ok, rows} when length(rows) == count ->
        {:ok, rows}

      {:ok, rows} ->
        # The wrong number of rows means the model lost its place partway down.
        # One retry is cheap; if that fails outright the first attempt still
        # gives the reviewer something to correct.
        case read_once(image_ref, count, opts) do
          {:ok, retried} -> {:ok, retried}
          {:error, _reason} -> {:ok, rows}
        end

      error ->
        error
    end
  end

  defp read_once(image_ref, count, opts) do
    with {:ok, text} <- ask(image_ref, read_prompt(count), @read_schema, opts),
         {:ok, %{"cards" => cards}} <- decode(text) do
      {:ok, cards |> Enum.sort_by(& &1["position"]) |> Enum.with_index(1) |> Enum.map(&row/1)}
    end
  end

  defp row({card, index}) do
    %{
      position: index,
      set: card["set"] |> to_string() |> String.trim() |> String.downcase(),
      collector_number: card["collector_number"] |> to_string() |> String.trim(),
      name: card["name"] |> to_string() |> String.trim(),
      foil: false
    }
  end

  defp read_prompt(count) do
    """
    This photograph contains EXACTLY #{count} Magic: The Gathering cards, counted
    and confirmed by a human. Report the set code and collector number for every
    one of them.

    The cards are usually fanned or stacked so most show only a thin horizontal
    strip along their bottom edge. That strip carries the collector line, which
    on a modern card reads left to right as: rarity letter, collector number,
    set code, language, then the artist name — for example "U 0089  HOB • EN
    ~ Andreia Ugrai" or "0042/0281  EOE • EN". The set code is the 3-4 character
    letter/digit group; the collector number is the digits before it.

    Rules:
    - Return exactly #{count} entries, numbered 1 to #{count} from the top of the
      photo down. Every visible card gets an entry, in order, with no gaps.
    - Read the set code as printed. Do not translate or normalise promo and
      variant codes, and do not substitute a set you think the card belongs to.
    - The small print on the right side of the card (the copyright line and its
      code) is NOT the set code. Use the group on the left, next to the language.
    - If a card's corner is genuinely unreadable, still emit its entry in
      sequence with empty strings for set and collector number. A gap is worse
      than a blank, because it silently shifts every card after it.
    """
  end

  # Cards per vision request when reading single-card images. Small enough that
  # a model keeps every label straight, large enough that a video of a hundred
  # cards is a dozen requests rather than a hundred.
  @batch_size 8
  @batch_concurrency 4

  @cards_schema %{
    type: "object",
    properties: %{
      cards: %{
        type: "array",
        items: %{
          type: "object",
          properties: %{
            card: %{
              type: "integer",
              description: "The label number of the image this entry describes (\"Card 3\" → 3)."
            },
            printed_name: %{
              type: "string",
              description:
                "The name in the card's title bar exactly as printed, in the card's own language. Empty string if unreadable."
            },
            collector_number: %{
              type: "string",
              description:
                "The collector number from the bottom-left collector line (e.g. \"0081\", \"112a\"). Empty string if unreadable."
            },
            set: %{
              type: "string",
              description:
                "The set code from the collector line (e.g. \"FRA\", \"EOE\", \"MH3\"). Empty string if unreadable."
            },
            foil_mark: %{
              type: "string",
              enum: ["star", "dot", "unreadable"],
              description:
                "The symbol between the set code and the language code: \"star\" for ★, \"dot\" for •."
            },
            language: %{
              type: "string",
              description:
                "The language code after that symbol (e.g. \"EN\", \"DE\", \"JP\"). Empty string if unreadable."
            }
          },
          required: ["card", "printed_name", "collector_number", "set", "foil_mark", "language"],
          additionalProperties: false
        }
      }
    },
    required: ["cards"],
    additionalProperties: false
  }

  @doc """
  Read a list of images that each hold exactly one card — the frames pulled
  from a video. Returns `{:ok, rows}` with one row per image, in order, as
  `%{position, set, collector_number, name, printed_name, language, foil, notes}`.

  Because each image is known to be one card, there is nothing to count: the
  row count is fixed before the model is asked anything, and a card that can't
  be read still gets a (blank) row rather than silently going missing.

  Foil comes from the printed collector line — a ★ between set and language
  on a foil, a • on a non-foil — never from how shiny the card looks. An
  unreadable mark is left non-foil and noted for the review.
  """
  def read_cards(images, opts \\ []) do
    rows =
      images
      |> Enum.with_index(1)
      |> Enum.chunk_every(@batch_size)
      |> Task.async_stream(&read_batch(&1, opts),
        max_concurrency: @batch_concurrency,
        timeout: :infinity,
        ordered: true
      )
      |> Enum.flat_map(fn {:ok, rows} -> rows end)

    {:ok, rows}
  end

  defp read_batch(batch, opts) do
    with {:ok, content} <- batch_content(batch),
         {:ok, text} <-
           Anthropic.generate(
             cards_prompt(length(batch)),
             [images: content, format: @cards_schema, max_tokens: @max_tokens] ++ opts
           ),
         {:ok, %{"cards" => cards}} <- decode(text) do
      card_rows(batch, cards)
    else
      error -> Enum.map(batch, fn {_image, position} -> unread_row(position, error) end)
    end
  end

  # Images are relabelled 1..n inside the batch so the prompt can say exactly
  # how many to expect, whatever their position in the video.
  defp batch_content(batch) do
    batch
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, []}, fn {{image, _position}, label}, {:ok, acc} ->
      with {:ok, ref} <- Image.prepare(image),
           {:ok, block} <- Anthropic.image_block(ref) do
        {:cont, {:ok, acc ++ [%{type: "text", text: "Card #{label}:"}, block]}}
      else
        error -> {:halt, error}
      end
    end)
  end

  @doc false
  # One row per image in the batch, matched by label rather than by order —
  # an entry the model skipped becomes a blank row, not a shift of every row
  # after it.
  def card_rows(batch, cards) do
    by_label = Map.new(cards, fn card -> {card["card"], card} end)

    batch
    |> Enum.with_index(1)
    |> Enum.map(fn {{_image, position}, label} ->
      case Map.fetch(by_label, label) do
        {:ok, card} -> card_row(position, card)
        :error -> unread_row(position, :not_returned)
      end
    end)
  end

  defp card_row(position, card) do
    printed = card["language"] |> to_string() |> String.trim()
    language = Language.scryfall_code(printed)
    printed_name = card["printed_name"] |> to_string() |> String.trim()

    notes =
      Enum.reject(
        [
          if(card["foil_mark"] == "unreadable", do: "foil mark unreadable — check for ★"),
          if(printed != "" and language == nil, do: "unknown language #{printed}")
        ],
        &is_nil/1
      )

    %{
      position: position,
      set: card["set"] |> to_string() |> String.trim() |> String.downcase(),
      collector_number: card["collector_number"] |> to_string() |> String.trim(),
      name: printed_name,
      printed_name: printed_name,
      language: language || "en",
      foil: card["foil_mark"] == "star",
      notes: notes
    }
  end

  defp unread_row(position, reason) do
    %{
      position: position,
      set: "",
      collector_number: "",
      name: "",
      printed_name: "",
      language: "en",
      foil: false,
      notes: ["not read — #{inspect(reason)}"]
    }
  end

  defp cards_prompt(count) do
    """
    Each of the #{count} images above is a photo of ONE Magic: The Gathering card,
    labelled "Card 1" to "Card #{count}". For every card, read:

    - printed_name: the name in the title bar, exactly as printed, in the card's
      own language.
    - collector_number and set: from the collector line in the bottom-left
      corner. On a modern card it is two short lines, for example

          C 0081
          FRA ★ DE

      The letter before the number is the rarity (C, U, R, M) and is not part of
      the number. The set code is the 3-4 character group that starts the second
      line.
    - foil_mark: the small symbol between the set code and the language code. A
      star (★) means the card is foil; a dot (•) means it is not. Report "star"
      or "dot", or "unreadable" if you genuinely cannot tell which. Judge this
      ONLY from the printed symbol — never from shine, glare or colour.
    - language: the code after that symbol (EN, DE, FR, IT, ES, PT, JP, KO, RU,
      CS, CT).

    Rules:
    - Return exactly #{count} entries, one per card, with "card" set to its label.
    - Read what is printed. Do not substitute a set or number you think the card
      ought to have.
    - The copyright line on the right of the bottom edge is not the collector line.
    - If something is genuinely unreadable, give an empty string rather than a
      guess. A blank gets checked by a human; a confident wrong guess does not.
    """
  end

  @doc """
  Look every row up on Scryfall, returning rows annotated with `:resolved`
  (boolean) and, when found, the canonical `:name`, `:set` and
  `:collector_number` from the printing.

  Doing this before the human review is the point: a row that reads
  "Bilbo's Gambit — hob 5" has plainly been read right, and one that stays
  unresolved is exactly what the reviewer needs to look at.
  """
  def resolve(rows) do
    rows
    |> Task.async_stream(&resolve_row/1, max_concurrency: 4, timeout: :infinity, ordered: true)
    |> Enum.map(fn {:ok, row} -> row end)
  end

  defp resolve_row(%{set: set, collector_number: number} = row)
       when set != "" and number != "" do
    # Scryfall asks for a small delay between requests; this is well inside it.
    Process.sleep(100)

    case Scryfall.card_by_set_number(set, number, row[:language]) do
      {:ok, printing} ->
        %{
          row
          | name: printing["name"],
            set: printing["set"],
            collector_number: printing["collector_number"]
        }
        |> Map.put(:resolved, true)
        |> check_name(printing)

      {:error, _reason} ->
        Map.put(row, :resolved, false)
    end
  end

  defp resolve_row(row), do: Map.put(row, :resolved, false)

  # A misread digit usually lands on a real card — just the wrong one — so a
  # resolved row is not yet a right row. When the name was read off the card
  # too, it has to agree with the printing Scryfall returned. Only compared in
  # the same language: a German name against an English fallback proves nothing.
  defp check_name(%{printed_name: read} = row, printing) when read != "" do
    names = printed_names(printing)
    same_language = printing["lang"] == Map.get(row, :language, "en")

    if same_language and not Enum.any?(names, &same_name?(read, &1)) do
      add_note(
        row,
        "name on card reads “#{read}”, #{row.set} #{row.collector_number} is “#{hd(names)}”"
      )
    else
      row
    end
  end

  defp check_name(row, _printing), do: row

  # Every name the card could be showing. A multi-face card (prepare, adventure,
  # split, transform) has no top-level printed name in a localised printing —
  # each face carries its own — and the title bar shows only the front face's.
  defp printed_names(printing) do
    faces =
      printing
      |> Map.get("card_faces", [])
      |> Enum.flat_map(fn face -> [face["printed_name"], face["name"]] end)

    [printing["printed_name"] | faces]
    |> Enum.concat([printing["name"]])
    |> Enum.reject(&(&1 in [nil, ""]))
  end

  defp same_name?(a, b), do: String.jaro_distance(normalise(a), normalise(b)) >= 0.85

  defp normalise(name), do: name |> String.downcase() |> String.replace(~r/[^\p{L}\p{N}]+/u, "")

  defp add_note(row, note), do: Map.update(row, :notes, [note], &(&1 ++ [note]))

  @doc """
  Render reviewed rows as Moxfield import CSV. Only resolved rows are included;
  identical printings (same set, collector number, foil and language) merge
  into one line with a count. Rows without a `:language` are English.
  """
  def to_csv(rows) do
    rows
    |> Enum.filter(& &1[:resolved])
    |> Enum.group_by(fn row -> {row.set, row.collector_number, row.foil, row[:language]} end)
    |> Enum.map(fn {_key, group} ->
      row = hd(group)

      %{
        count: length(group),
        name: row.name,
        edition: row.set,
        collector_number: row.collector_number,
        foil: row.foil,
        language: Language.moxfield_name(row[:language])
      }
    end)
    |> Enum.sort_by(& &1.name)
    |> Moxfield.to_csv()
  end

  @doc """
  Expand image references, replacing any local directory with the image and
  video files directly inside it (sorted by name, not recursive). URLs, plain file paths and
  `{media_type, base64}` tuples pass through untouched.
  """
  def expand_refs(image_refs) do
    image_refs |> List.wrap() |> Enum.flat_map(&expand_ref/1)
  end

  defp expand_ref("http://" <> _ = url), do: [url]
  defp expand_ref("https://" <> _ = url), do: [url]

  defp expand_ref(path) when is_binary(path) do
    if File.dir?(Path.expand(path)) do
      path
      |> Path.expand()
      |> File.ls!()
      |> Enum.filter(&image?/1)
      |> Enum.sort()
      |> Enum.map(&Path.join(path, &1))
    else
      [path]
    end
  end

  defp expand_ref(other), do: [other]

  defp image?(name) do
    extension = name |> Path.extname() |> String.downcase()
    extension in @image_extensions or extension in Video.extensions()
  end

  @doc """
  Returns a warning string when an image is small enough that the corner print
  is likely unreadable, or `nil`. Messaging-app photos are the usual culprit —
  they arrive re-encoded down to a fraction of the camera's resolution, and no
  amount of prompting recovers detail that isn't in the pixels.

  Measured in pixels where possible, because file size lies across formats: a
  HEIC and a JPEG of the same photo differ about twofold in bytes and not at
  all in detail. Byte size is the fallback when dimensions can't be read.
  """
  def low_resolution_warning(ref) do
    case Image.dimensions(ref) do
      {:ok, width, height} -> pixel_warning(ref, max(width, height))
      :error -> byte_warning(ref)
    end
  end

  defp pixel_warning(ref, long_edge) when long_edge < @low_resolution_edge do
    "#{Path.basename(ref)} is #{long_edge}px on its long edge, against the #{Image.max_edge()}px the model can use — corner print may be unreadable. The camera original scans much better than a messaging-app copy."
  end

  defp pixel_warning(_ref, _long_edge), do: nil

  defp byte_warning(path) when is_binary(path) do
    case File.stat(Path.expand(path)) do
      {:ok, %{size: size}} when size < @low_resolution_bytes ->
        "#{Path.basename(path)} is only #{div(size, 1024)} KB — corner print may be unreadable. The camera original scans much better than a messaging-app copy."

      _ ->
        nil
    end
  end

  defp byte_warning(_ref), do: nil

  defp ask(image_ref, prompt, schema, opts) do
    with {:ok, ref} <- Image.prepare(image_ref),
         {:ok, block} <- Anthropic.image_block(ref) do
      Anthropic.generate(
        prompt,
        [images: [block], format: schema, max_tokens: @max_tokens] ++ opts
      )
    end
  end

  defp decode(text) do
    case Jason.decode(text) do
      {:ok, map} -> {:ok, map}
      {:error, _} -> {:error, {:bad_vision_json, text}}
    end
  end
end
