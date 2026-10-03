defmodule Mix.Tasks.Mtg.Import do
  @shortdoc "Scan photos of cards into a Moxfield import CSV, reviewed once at the end"

  @default_out "reports/import.csv"

  @moduledoc """
  Read the set code + collector number off every card in a photo and write a
  Moxfield-importable CSV, with a single review pass once every photo is read.

      mix mtg.import https://example.com/my_cards.jpg
      mix mtg.import path/to/photo.jpg
      mix mtg.import front.jpg back.jpg --out reports/new_cards.csv
      mix mtg.import photos/2026-08-01 --out reports/new_cards.csv

  Accepts one or more image or video references: http(s) URLs, local file
  paths, or a directory, which stands in for every image and video file
  directly inside it (not recursive). AirDropped iPhone originals (`.heic`) are
  transcoded to JPEG on the way to the API, so a folder straight out of AirDrop
  works as-is.

  ## Videos

      mix mtg.import IMG_1815.MOV IMG_1816.MOV

  A video (`.mov`, `.mp4`, `.m4v`; needs `ffmpeg`) is read as a slideshow of
  single cards: hold each card still for a second or two, then take it fully
  out of frame before the next. The gap is what separates two cards, so
  duplicates can be shown back to back. Record in 4K if you can — the collector
  line is the smallest print on the card.

  Each card's sharpest still frame is cropped to the card and read for its
  name, set code, collector number, language and foil mark, then looked up on
  Scryfall in that language. **Foils need no input**: modern cards print a ★
  between the set code and language on a foil and a • on a non-foil, and that
  mark is what is read. A row is flagged for the review when the mark can't be
  read, or when the name on the card doesn't match the printing its number
  points at. Finding the cards takes a minute or two per video (cached, so a
  re-run starts reading at once); the card images are listed in the review.

  ## Photos

  Every image is scanned unattended:

    1. **Count.** Several independent passes count the cards and the consensus
       is used. Disagreement between passes is printed, because that is the
       signal that a photo needs a second look.
    2. **Read.** The set code and collector number are read for exactly that
       many cards and looked up on Scryfall, so rows carry real card names and
       an unmatched row stands out.

  Then, once, for everything scanned:

    3. **Review.** One table of every row, grouped by photo or video. Correct,
       drop or add rows until it matches the cards in your hand. A language
       code can follow the number (`3 fra 81 de`); a fixed row keeps its own.
    4. **Foils.** You say which rows are foil — for a video, you confirm the
       ones read off the ★.

  The CSV is rewritten after each image and again after the review, so an
  interrupted run keeps its work. Cards are identified against Scryfall, so you
  need to be online.

  Options:

    * `--out FILE` — where to write the CSV (default `#{@default_out}`)
    * `--passes N` — independent counting passes per image (default 3)
    * `--yes` — skip the review entirely; only foils read off a ★ are marked

  Requires an Anthropic API key (env `ANTHROPIC_API_KEY` or
  `~/.config/anthropic/token`). Import the result at Moxfield → Collection → Import.
  """

  use Mix.Task

  alias DeckManager.{CardScanner, Language, Video}

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")

    {opts, refs, _} =
      OptionParser.parse(argv, strict: [out: :string, passes: :integer, yes: :boolean])

    case CardScanner.expand_refs(refs) do
      [] when refs == [] ->
        Mix.shell().error(
          "usage: mix mtg.import <image-url-path-or-directory> [more...] [--out FILE]"
        )

      [] ->
        Mix.shell().error("No images found in #{Enum.join(refs, ", ")}")

      images ->
        import_cards(images, opts)
    end
  end

  defp import_cards(images, opts) do
    out = Keyword.get(opts, :out, @default_out)
    total = length(images)

    scanned =
      images
      |> Enum.with_index(1)
      |> Enum.reduce([], fn {ref, index}, acc ->
        Mix.shell().info("\n#{IO.ANSI.bright()}[#{index}/#{total}] #{label(ref)}#{reset()}")

        scan = if Video.video?(ref), do: scan_video(ref), else: scan_image(ref, opts)

        case scan do
          {:ok, rows} ->
            acc = acc ++ rows
            # Written after every image, so an interrupted run keeps its work.
            write(out, acc)
            acc

          {:error, reason} ->
            Mix.shell().error("  ! scan failed — #{inspect(reason)}")
            acc
        end
      end)
      |> renumber()

    if scanned == [] do
      Mix.shell().error("\nNo cards to write — #{out} left untouched.")
    else
      # The file already holds the pre-review rows, so it is rewritten even if
      # the review emptied it — otherwise a dropped row survives on disk.
      rows = review(scanned, opts)
      write(out, rows)
      finish(rows, out)
    end
  end

  defp finish(rows, out) do
    {kept, dropped} = Enum.split_with(rows, & &1.resolved)
    foils = Enum.count(kept, & &1.foil)

    Mix.shell().info(
      "\nWrote #{out} — #{length(kept)} card(s), #{foils} foil. " <>
        "Import at Moxfield → Collection → Import."
    )

    if dropped != [] do
      Mix.shell().error("  #{length(dropped)} unresolved row(s) left out:")
      Enum.each(dropped, fn row -> Mix.shell().error("    #{describe(row)}") end)
    end

    # Only reachable with flags still on them under --yes, or when a row was
    # deliberately left as it was — either way, worth a look in Moxfield.
    case Enum.filter(kept, &notes?/1) do
      [] ->
        :ok

      flagged ->
        Mix.shell().info("  #{length(flagged)} written row(s) carry a note:")

        Enum.each(flagged, fn row ->
          Mix.shell().info("    #{pad(row.position)}  #{describe(row)}")
        end)
    end
  end

  # Find the cards, read them in batches, resolve. Nothing is asked here either:
  # the review at the end is where a flagged row gets looked at.
  defp scan_video(ref) do
    Mix.shell().info("  Finding cards (decoding the video takes a minute or two) ...")

    with {:ok, cards} <- Video.cards(ref) do
      report_cards(cards)
      Mix.shell().info("  Reading #{length(cards)} card(s) ...")
      {:ok, rows} = CardScanner.read_cards(Enum.map(cards, & &1.image))

      rows =
        rows
        |> Enum.zip(cards)
        |> Enum.map(fn {row, card} -> from_video(row, card) end)
        |> CardScanner.resolve()
        |> Enum.map(&Map.put(&1, :source, label(ref)))

      report_reads(rows)
      {:ok, rows}
    end
  end

  defp from_video(row, card) do
    row = Map.merge(row, %{at: card.at, image: card.image})

    if card.brief,
      do: Map.update!(row, :notes, &(&1 ++ ["barely shown — image may be blurred"])),
      else: row
  end

  defp report_cards(cards) do
    Mix.shell().info("  #{length(cards)} card(s) found.")

    case Enum.count(cards, & &1.brief) do
      0 ->
        :ok

      brief ->
        Mix.shell().error("  ! #{brief} shown too briefly to hold still — check them below.")
    end
  end

  # Count then read, unattended. Nothing is asked here: a photo that went wrong
  # shows up in the one review at the end, and stopping twenty times to say "yes"
  # is worse than fixing three rows once.
  defp scan_image(ref, opts) do
    Enum.each(List.wrap(CardScanner.low_resolution_warning(ref)), fn warning ->
      Mix.shell().info("  #{IO.ANSI.yellow()}note: #{warning}#{reset()}")
    end)

    passes = Keyword.get(opts, :passes, 3)
    Mix.shell().info("  Counting cards (#{passes} passes) ...")

    case CardScanner.count(ref, passes: passes) do
      {:ok, tally} ->
        report_counts(tally)
        read_cards(ref, tally.count)

      error ->
        error
    end
  end

  defp report_counts(%{counts: counts, count: count, requested: requested} = tally) do
    if Enum.uniq(counts) == [count] do
      Mix.shell().info("  #{length(counts)}/#{requested} passes agree: #{count} card(s).")
    else
      spread = counts |> Enum.sort() |> Enum.join(", ")

      # Nothing stops on this any more, so it has to read as something to check
      # when the table comes up rather than as progress noise.
      Mix.shell().error("  ! passes disagree (#{spread}) — going with #{count}, check it below.")
    end

    # A pass that died is a smaller sample, not a smaller problem — say so
    # rather than letting "2/3 agree" read like a clean result.
    if tally.failed > 0 do
      Mix.shell().error(
        "  ! #{tally.failed} of #{requested} counting pass(es) failed — #{inspect(tally.error)}"
      )
    end
  end

  # Read the corners for the counted cards and resolve against Scryfall. Rows
  # carry the photo they came from, so the review at the end can group them and
  # a bad row sits next to the card it was read off.
  defp read_cards(ref, count) do
    Mix.shell().info("  Reading #{count} collector line(s) ...")

    case CardScanner.read(ref, count, []) do
      {:ok, rows} ->
        if length(rows) != count do
          Mix.shell().error(
            "  ! model returned #{length(rows)} row(s) for #{count} card(s) — fix at the review"
          )
        end

        rows =
          rows
          |> CardScanner.resolve()
          |> Enum.map(&Map.put(&1, :source, label(ref)))

        report_reads(rows)
        {:ok, rows}

      error ->
        error
    end
  end

  defp report_reads(rows) do
    case Enum.count(rows, &(not &1.resolved)) do
      0 ->
        Mix.shell().info("  #{length(rows)} row(s), all matched on Scryfall.")

      unresolved ->
        Mix.shell().error(
          "  #{length(rows)} row(s), #{unresolved} unmatched — fix at the review."
        )
    end

    foils = Enum.count(rows, & &1.foil)
    flagged = Enum.count(rows, &(&1.resolved and notes?(&1)))

    if foils > 0, do: Mix.shell().info("  #{foils} foil (★ on the card).")

    if flagged > 0,
      do: Mix.shell().error("  #{flagged} matched row(s) flagged — check at the review.")
  end

  # Step 3: one review over everything scanned, then one pass of foils. Asking
  # per image meant sitting at the terminal for the whole run; the corrections
  # are the same corrections whenever they are made.
  defp review(rows, opts) do
    if Keyword.get(opts, :yes, false) do
      rows
    else
      Mix.shell().info("\n#{IO.ANSI.bright()}Review#{reset()}")

      rows
      |> correct()
      |> foils()
    end
  end

  defp correct(rows) do
    print_table(rows)
    edits(rows)
  end

  # The table is printed once and each edit echoes only the row it touched —
  # a hundred rows off a folder of photos is too much to reprint per keystroke,
  # so `p` asks for it when you have lost your place.
  defp edits(rows) do
    case ask(
           "  Corrections? [none] (N set num · d N · + set num · p reprint · Enter when right): "
         ) do
      answer when answer in ["", "y", "done"] -> rows
      "p" -> correct(rows)
      answer -> edits(edit(rows, answer))
    end
  end

  defp edit(rows, command) do
    case String.split(command, ~r/\s+/, trim: true) do
      ["d", index] ->
        with_index(rows, index, fn row ->
          Mix.shell().info("    dropped #{describe(row)}")
          Enum.reject(rows, &(&1.position == row.position))
        end)

      ["+", set, number | language] when length(language) <= 1 ->
        with {:ok, language} <- language(language, "en") do
          added =
            lookup(%{
              position: next_position(rows),
              set: set,
              collector_number: number,
              name: "",
              language: language,
              foil: false,
              source: "added by hand"
            })

          Mix.shell().info("    #{pad(added.position)}  #{describe(added)}")
          rows ++ [added]
        else
          :error -> bad_language(rows, language)
        end

      [index, set, number | language] when length(language) <= 1 ->
        with_index(rows, index, fn row ->
          case language(language, Map.get(row, :language, "en")) do
            {:ok, language} ->
              fixed =
                lookup(Map.merge(row, %{set: set, collector_number: number, language: language}))

              Mix.shell().info("    #{pad(row.position)}  #{describe(fixed)}")
              replace(rows, fixed)

            :error ->
              bad_language(rows, language)
          end
        end)

      _ ->
        Mix.shell().error(
          "  ? try: `3 hob 124` to fix row 3, `3 fra 81 de` to fix it in German, " <>
            "`d 5` to drop row 5, `+ hob 44` to add"
        )

        rows
    end
  end

  # An optional trailing language code on an edit; absent keeps `default`.
  defp language([], default), do: {:ok, default}

  defp language([code], _default) do
    case Language.scryfall_code(code) do
      nil -> :error
      language -> {:ok, language}
    end
  end

  defp bad_language(rows, [code]) do
    Mix.shell().error("  ? #{code} is not a language code — e.g. en, de, fr, it, es, jp")
    rows
  end

  # Row numbers are handed out once and never reshuffled mid-review: the table
  # is printed once, so a drop that renumbered everything below it would turn
  # the numbers on screen into lies.
  defp next_position(rows), do: (rows |> Enum.map(& &1.position) |> Enum.max(fn -> 0 end)) + 1

  defp with_index(rows, index, fun) do
    case Integer.parse(index) do
      {number, _} ->
        case Enum.find(rows, &(&1.position == number)) do
          nil ->
            Mix.shell().error("  ? no row #{number}")
            rows

          row ->
            fun.(row)
        end

      :error ->
        Mix.shell().error("  ? #{index} is not a row number")
        rows
    end
  end

  # A row you have just corrected starts with a clean slate: its old notes were
  # about the old reading. The name check runs again against the new printing.
  defp lookup(row) do
    row
    |> Map.merge(%{
      set: row.set |> String.trim() |> String.downcase(),
      collector_number: String.trim(row.collector_number),
      notes: []
    })
    |> List.wrap()
    |> CardScanner.resolve()
    |> hd()
  end

  defp replace(rows, row) do
    Enum.map(rows, fn existing ->
      if existing.position == row.position, do: row, else: existing
    end)
  end

  defp renumber(rows) do
    rows |> Enum.with_index(1) |> Enum.map(fn {row, index} -> %{row | position: index} end)
  end

  # Step 4: foils. The model never guesses from sheen — on a photo the person
  # holding the cards says which; off a video the ★ printed on the card already
  # has, and this just confirms it. A wrong answer silently creates the wrong
  # printing, so either way it is put to a human once.
  defp foils(rows) do
    marked = rows |> Enum.filter(& &1.foil) |> Enum.map(& &1.position)

    prompt =
      case marked do
        [] ->
          "  Which are foil? (e.g. `2 5-7`, `all`, Enter for none): "

        marked ->
          "  Foil, from the ★ on the card: #{Enum.join(marked, " ")}. " <>
            "Enter to keep, or list every foil row (`none` for none): "
      end

    case ask(prompt) do
      "" ->
        rows

      "none" ->
        Enum.map(rows, &%{&1 | foil: false})

      "all" ->
        Enum.map(rows, &%{&1 | foil: true})

      answer ->
        # Against the highest row number, not the row count: dropping a row
        # during the review leaves a gap rather than shuffling the numbers.
        case parse_rows(answer, next_position(rows) - 1) do
          {:ok, picked} ->
            marked = Enum.map(rows, &%{&1 | foil: &1.position in picked})
            Mix.shell().info("  #{Enum.count(marked, & &1.foil)} marked foil.")
            marked

          :error ->
            Mix.shell().error(
              "  ? row numbers between 1 and #{next_position(rows) - 1}, ranges allowed"
            )

            foils(rows)
        end
    end
  end

  defp parse_rows(answer, max) do
    answer
    |> String.split([",", " "], trim: true)
    |> Enum.reduce_while([], fn token, acc ->
      case parse_token(token, max) do
        {:ok, numbers} -> {:cont, acc ++ numbers}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      :error -> :error
      [] -> :error
      numbers -> {:ok, MapSet.new(numbers)}
    end
  end

  defp parse_token(token, max) do
    case String.split(token, "-", parts: 2) do
      [single] -> parse_number(single, max) |> wrap_range(max)
      [from, to] -> parse_range(from, to, max)
    end
  end

  defp wrap_range({:ok, number}, _max), do: {:ok, [number]}
  defp wrap_range(:error, _max), do: :error

  defp parse_range(from, to, max) do
    with {:ok, first} <- parse_number(from, max),
         {:ok, last} <- parse_number(to, max),
         true <- first <= last do
      {:ok, Enum.to_list(first..last)}
    else
      _ -> :error
    end
  end

  defp parse_number(text, max) do
    case Integer.parse(String.trim(text)) do
      {number, ""} when number >= 1 -> if number <= max, do: {:ok, number}, else: :error
      _ -> :error
    end
  end

  # Grouped by photo, because a run of wrong rows almost always means one bad
  # photo rather than one bad card.
  defp print_table(rows) do
    Mix.shell().info("    #   set   num    card")

    rows
    |> Enum.chunk_by(& &1.source)
    |> Enum.each(fn group ->
      Mix.shell().info("  #{IO.ANSI.faint()}#{hd(group).source}#{images(group)}#{reset()}")

      Enum.each(group, fn row ->
        Mix.shell().info("    #{pad(row.position)}  #{describe(row)}")
      end)
    end)
  end

  # Where a video's card images are, so a flagged row can be looked at — the
  # `@1:23` on each row is the same card in the video itself.
  defp images(group) do
    case Enum.find(group, & &1[:image]) do
      nil -> ""
      row -> " — card images in #{Path.dirname(row.image)}"
    end
  end

  defp describe(%{resolved: true} = row) do
    "#{cell(row.set, 5)} #{cell(row.collector_number, 6)} #{row.name}#{extras(row)}"
  end

  defp describe(row) do
    label = if row.name == "", do: "(unreadable)", else: row.name

    "#{IO.ANSI.red()}#{cell(row.set, 5)} #{cell(row.collector_number, 6)} ?? #{label}#{reset()}" <>
      extras(row)
  end

  # Foil, a non-English language, where in the video, and anything to check.
  defp extras(row) do
    foil = if row.foil, do: " ★", else: ""

    language =
      case Map.get(row, :language, "en") do
        "en" -> ""
        language -> " [#{String.upcase(language)}]"
      end

    at =
      case row[:at] do
        nil -> ""
        seconds -> " #{IO.ANSI.faint()}@#{timestamp(seconds)}#{reset()}"
      end

    notes =
      if notes?(row),
        do: " #{IO.ANSI.yellow()}! #{Enum.join(row.notes, "; ")}#{reset()}",
        else: ""

    foil <> language <> at <> notes
  end

  defp notes?(row), do: Map.get(row, :notes, []) != []

  defp timestamp(seconds) do
    total = trunc(seconds)
    "#{div(total, 60)}:#{total |> rem(60) |> to_string() |> String.pad_leading(2, "0")}"
  end

  defp cell(value, width), do: value |> to_string() |> String.pad_trailing(width)
  defp pad(number), do: number |> to_string() |> String.pad_leading(3)

  defp write(out, rows) do
    File.mkdir_p!(Path.dirname(out))
    File.write!(out, CardScanner.to_csv(rows))
  end

  defp ask(prompt) do
    case Mix.shell().prompt(prompt) do
      answer when is_binary(answer) -> answer |> String.trim() |> String.downcase()
      _ -> ""
    end
  end

  defp reset, do: IO.ANSI.reset()

  defp label(ref) when is_binary(ref), do: Path.basename(ref)
  defp label(_ref), do: "image"
end
