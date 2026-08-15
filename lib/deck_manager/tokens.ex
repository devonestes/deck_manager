defmodule DeckManager.Tokens do
  @moduledoc """
  Works out which tokens (and emblems) each decklist needs.

  Every line in `decks/<deck>.txt` names an exact printing, so we hand those
  printings to Scryfall's `/cards/collection` endpoint and read their
  `all_parts` links — the same relationships Scryfall shows under "Tokens" on a
  card page. The linked token printings are fetched once more to pick up stats,
  colors and rules text, which `all_parts` doesn't carry.

  Both halves of that lookup are cached in `data/scryfall/token_parts.json`
  (gitignored), keyed by printing, so a re-run only hits the network for cards
  it hasn't seen before.

  The rendered list lands in `tokens/<deck>.txt`, which *is* tracked in git:
  after `mix download`, `git diff tokens/` shows how each deck's token needs
  changed. `tokens/totals.txt` sums those lists across every active deck, so you
  can see how many copies of a token to bring in total.
  """

  require Logger

  alias DeckManager.Scryfall

  @cache_path "data/scryfall/token_parts.json"
  @out_dir "tokens"
  @totals_file "totals.txt"

  @doc """
  Regenerate `tokens/<deck>.txt` for each named deck, reusing one loaded cache
  for the whole run. Pass `force: true` to re-ask Scryfall about printings we've
  already looked up.
  """
  def write_all(decks, opts \\ []) do
    cache = if Keyword.get(opts, :force, false), do: empty_cache(), else: load_cache()
    File.mkdir_p!(@out_dir)

    {_results, cache} =
      Enum.map_reduce(decks, cache, fn deck, cache ->
        case for_deck(deck, cache) do
          {:ok, tokens, cache} ->
            File.write!(path(deck), render(tokens))
            {:ok, cache}

          {:error, reason, cache} ->
            Logger.warning("Could not list tokens for #{deck} - #{describe(reason)}")
            {:error, cache}
        end
      end)

    save_cache(cache)
    :ok
  end

  @doc """
  Tally `tokens/totals.txt`: every token any active deck needs, prefixed with
  how many decks need it, most-wanted first. Reads the per-deck files rather
  than Scryfall, so the totals can't drift from the lists they're drawn from.
  """
  def write_totals(decks) do
    body =
      decks
      |> Enum.map(&{&1, path(&1)})
      |> Enum.filter(fn {_deck, path} -> File.exists?(path) end)
      |> Enum.map(fn {deck, path} -> {deck, File.read!(path)} end)
      |> totals()

    File.write!(Path.join(@out_dir, @totals_file), body)
  end

  @doc """
  Count how many of the given `{deck, rendered}` pairs list each token, naming
  the decks that want it underneath.

  Tokens that only one deck needs are collected under that deck instead, so the
  tail of the file reads as "and these are the ones only <deck> asks for"
  rather than a hundred separate entries of one.

      2 Treasure (Artifact — Treasure)
          aesi
          gitrog_ride

      chatterfang
          Squirrel (1/1 green Creature — Squirrel)
  """
  def totals(rendered_decks) do
    {shared, sole} =
      rendered_decks
      |> Enum.flat_map(fn {deck, body} ->
        body |> String.split("\n", trim: true) |> Enum.uniq() |> Enum.map(&{&1, deck})
      end)
      |> Enum.group_by(fn {token, _deck} -> token end, fn {_token, deck} -> deck end)
      |> Enum.split_with(fn {_token, decks} -> length(decks) > 1 end)

    [by_token(shared), by_deck(sole)]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  defp by_token(shared) do
    shared
    |> Enum.sort_by(fn {token, decks} -> {-length(decks), token} end)
    |> Enum.map_join(fn {token, decks} ->
      "#{length(decks)} #{token}\n" <> Enum.map_join(Enum.sort(decks), &"    #{&1}\n")
    end)
  end

  defp by_deck(sole) do
    sole
    |> Enum.group_by(fn {_token, [deck]} -> deck end, fn {token, _decks} -> token end)
    |> Enum.sort()
    |> Enum.map_join("\n", fn {deck, tokens} ->
      "#{deck}\n" <> Enum.map_join(Enum.sort(tokens), &"    #{&1}\n")
    end)
  end

  @doc """
  The distinct tokens a deck needs, as trimmed Scryfall token maps sorted by
  name. Threads the printing cache through so callers can reuse it.
  """
  def for_deck(deck, cache) do
    path = "decks/#{deck}.txt"

    case File.read(path) do
      {:error, reason} ->
        {:error, {:unreadable, path, reason}, cache}

      {:ok, body} ->
        {cards, unparsed} = identifiers(body)
        Enum.each(unparsed, &Logger.warning("#{deck}: could not read line #{inspect(&1)}"))

        cache = cache |> fetch_parts(cards) |> fetch_tokens()
        {:ok, collect(cards, cache), cache}
    end
  end

  @doc """
  Parse a decklist into `{printings, unparsed_lines}`.

  Lines look like `1 Arcane Denial (ALL) 22a` — the set code and collector
  number are the identity Scryfall indexes on, and the printed name is kept for
  attributing tokens back to the card that makes them.
  """
  def identifiers(body) do
    body
    |> String.trim()
    |> String.split("\n", trim: true)
    |> Enum.reduce({[], []}, fn line, {cards, unparsed} ->
      case Regex.run(~r/^\s*\d+\s+(.+?)\s+\(([^)]+)\)\s+(\S+)/, line) do
        [_, name, set, number] ->
          card = %{
            name: String.replace(name, " / ", " // "),
            set: String.downcase(set),
            number: number
          }

          {[card | cards], unparsed}

        nil ->
          {cards, [line | unparsed]}
      end
    end)
    |> then(fn {cards, unparsed} -> {Enum.reverse(cards), Enum.reverse(unparsed)} end)
  end

  @doc """
  Render tokens as the contents of a `tokens/<deck>.txt` file: one line per
  distinct token. Rules text follows in brackets, which is what separates two
  tokens that share a name and stats.

      Spirit (1/1 white Creature — Spirit)
      Spirit (1/1 white Creature — Spirit) [Flying]
  """
  def render(tokens) do
    Enum.map_join(tokens, fn token ->
      "#{token["name"]} (#{descriptor(token)})#{rules(token)}\n"
    end)
  end

  # --- lookup -------------------------------------------------------------

  # Ask Scryfall about any printing we haven't already recorded token links for.
  # A printing that makes no tokens caches as `[]`, so it's asked about once.
  defp fetch_parts(cache, cards) do
    names = Map.new(cards, &{printing_key(&1), &1.name})

    unknown =
      names
      |> Map.keys()
      |> Enum.reject(&Map.has_key?(cache["printings"], &1))

    if unknown == [] do
      cache
    else
      identifiers =
        Enum.map(unknown, fn key ->
          [set, number] = String.split(key, "/", parts: 2)
          %{"set" => set, "collector_number" => number}
        end)

      {found, _missing} = Scryfall.cards_by_identifiers(identifiers)

      printings =
        Enum.reduce(found, cache["printings"], fn card, acc ->
          Map.put(acc, printing_key(card), token_ids(card))
        end)

      unknown
      |> Enum.reject(&Map.has_key?(printings, &1))
      |> by_name(names, printings)
      |> then(&%{cache | "printings" => &1})
    end
  end

  # Moxfield and Scryfall occasionally disagree about a collector number, so a
  # printing we can't find is looked up by name instead. Which printing we land
  # on barely matters — token links are the same across a card's printings far
  # more often than not, and a wrong-but-close answer beats silently dropping
  # every token that card makes.
  defp by_name([], _names, printings), do: printings

  defp by_name(unresolved, names, printings) do
    identifiers = Enum.map(unresolved, &%{"name" => names[&1]})
    {found, _missing} = Scryfall.cards_by_identifiers(identifiers)
    by_name = Map.new(found, &{String.downcase(&1["name"]), &1})

    Enum.reduce(unresolved, printings, fn key, acc ->
      case Map.get(by_name, String.downcase(names[key])) do
        nil ->
          Logger.warning("No Scryfall card for #{names[key]} (#{key})")
          acc

        card ->
          Logger.warning("#{names[key]}: no printing #{key}, used #{printing_key(card)} instead")
          Map.put(acc, key, token_ids(card))
      end
    end)
  end

  # `all_parts` also links combo pieces and meld halves; only the token
  # component (which covers emblems) is something you have to bring to a game.
  defp token_ids(card) do
    card
    |> Map.get("all_parts", [])
    |> Kernel.||([])
    |> Enum.filter(fn part -> part["component"] == "token" end)
    |> Enum.map(fn part -> part["id"] end)
  end

  # `all_parts` carries only name and type line, so fetch the token printings
  # themselves for power, toughness, colors and the oracle id we dedupe on.
  defp fetch_tokens(cache) do
    unknown =
      cache["printings"]
      |> Map.values()
      |> List.flatten()
      |> Enum.uniq()
      |> Enum.reject(&Map.has_key?(cache["tokens"], &1))

    if unknown == [] do
      cache
    else
      {found, missing} = Scryfall.cards_by_identifiers(Enum.map(unknown, &%{"id" => &1}))
      Enum.each(missing, &Logger.warning("No Scryfall token for #{inspect(&1)}"))

      tokens =
        Enum.reduce(found, cache["tokens"], fn token, acc ->
          Map.put(acc, token["id"], trim(token))
        end)

      %{cache | "tokens" => tokens}
    end
  end

  @token_fields ~w(oracle_id name type_line oracle_text power toughness colors layout)

  defp trim(token) do
    token
    |> Map.take(@token_fields)
    |> Map.put("card_faces", Enum.map(token["card_faces"] || [], &Map.take(&1, @token_fields)))
  end

  # One entry per distinct token, keyed on oracle id so two Beasts with
  # different stats stay apart while the same Treasure from six cards collapses.
  defp collect(cards, cache) do
    cards
    |> Enum.flat_map(fn card ->
      cache["printings"]
      |> Map.get(printing_key(card), [])
      |> Enum.map(&{Map.get(cache["tokens"], &1), card.name, &1})
    end)
    |> Enum.filter(fn
      {nil, source, id} ->
        Logger.warning("No cached token #{id} (linked from #{source})")
        false

      _ ->
        true
    end)
    |> Enum.map(fn {token, _source, _id} -> token end)
    |> Enum.uniq_by(fn token -> token["oracle_id"] end)
    |> Enum.sort_by(fn token ->
      {String.downcase(token["name"]), descriptor(token), rules(token)}
    end)
  end

  # --- rendering ----------------------------------------------------------

  @colors %{"W" => "white", "U" => "blue", "B" => "black", "R" => "red", "G" => "green"}

  # Double-faced tokens carry their stats per face, so describe both sides.
  defp descriptor(%{"layout" => "double_faced_token", "card_faces" => [_ | _] = faces}) do
    Enum.map_join(faces, " // ", &face_descriptor/1)
  end

  defp descriptor(token), do: face_descriptor(token)

  defp face_descriptor(token) do
    [stats(token), colors(token), type(token)]
    |> Enum.reject(&(&1 == nil))
    |> Enum.join(" ")
  end

  defp stats(%{"power" => power, "toughness" => toughness})
       when is_binary(power) and is_binary(toughness),
       do: "#{power}/#{toughness}"

  defp stats(_), do: nil

  # What actually separates the two 1/1 white Spirits you own: one is blank and
  # the other says "Flying". Scryfall derives a token's `keywords` from this
  # same text, so printing the text covers them without saying it twice.
  defp rules(%{"layout" => "double_faced_token", "card_faces" => [_ | _] = faces}) do
    faces
    |> Enum.map(fn face -> {face["name"], text(face)} end)
    |> Enum.reject(fn {_name, text} -> text == "" end)
    |> case do
      [] ->
        ""

      faces ->
        " [" <> Enum.map_join(faces, "; ", fn {name, text} -> "#{name}: #{text}" end) <> "]"
    end
  end

  defp rules(token) do
    case text(token) do
      "" -> ""
      text -> " [#{text}]"
    end
  end

  # These tokens read the same everywhere they turn up, so their text says
  # nothing you don't already know. The 0/0 Construct is the Karnstruct, always
  # "+1/+1 for each artifact"; Constructs with printed stats vary, so they keep
  # their text.
  @boilerplate [
    "Agate Instigator",
    "Beau",
    "Blood",
    "Clue",
    "Eldrazi Scion",
    "Eldrazi Spawn",
    "Everywhere",
    "Fanatic of Rhonas",
    "Food",
    "Incubator",
    "Iridescent Vinelasher",
    "Map",
    "Powerstone",
    "Shard",
    "Sicarian Infiltrator",
    "Treasure"
  ]

  defp text(%{"name" => "Construct", "power" => "0", "toughness" => "0"}), do: ""
  defp text(%{"name" => name}) when name in @boilerplate, do: ""

  # Reminder text is dead weight on a list you're reading to tell two tokens
  # apart — it's the same on every token that has the keyword.
  defp text(token) do
    (token["oracle_text"] || "")
    |> String.replace(~r/\s*\([^()]*\)/, "")
    |> String.split("\n", trim: true)
    |> Enum.map_join("; ", &String.trim/1)
  end

  # Only creatures get a color, so a Treasure reads as "Artifact — Treasure"
  # rather than "colorless Artifact — Treasure".
  defp colors(%{"power" => power} = token) when is_binary(power) do
    case token["colors"] || [] do
      [] -> "colorless"
      colors -> colors |> Enum.map(&Map.get(@colors, &1, &1)) |> Enum.join("/")
    end
  end

  defp colors(_), do: nil

  # Token type lines are prefixed "Token " ("Token Creature — Squirrel"), which
  # is noise in a file that's entirely tokens. Copy tokens are just "Token".
  defp type(%{"type_line" => "Token"}), do: "copy"
  defp type(%{"type_line" => type}) when is_binary(type), do: String.replace(type, "Token ", "")
  defp type(_), do: nil

  # --- cache --------------------------------------------------------------

  defp printing_key(%{set: set, number: number}), do: "#{set}/#{number}"
  defp printing_key(%{"set" => set, "collector_number" => number}), do: "#{set}/#{number}"

  defp path(deck), do: Path.join(@out_dir, "#{deck}.txt")

  # Bump when the shape of what we keep per token changes, so an older cache is
  # refetched rather than rendering the fields it was never asked for as blank.
  @cache_version 2

  defp empty_cache, do: %{"version" => @cache_version, "printings" => %{}, "tokens" => %{}}

  defp load_cache do
    with {:ok, body} <- File.read(@cache_path),
         %{"version" => @cache_version} = cache <- Jason.decode!(body) do
      Map.merge(empty_cache(), cache)
    else
      _ -> empty_cache()
    end
  end

  defp save_cache(cache) do
    File.mkdir_p!(Path.dirname(@cache_path))
    File.write!(@cache_path, Jason.encode!(cache))
  end

  defp describe({:unreadable, path, reason}), do: "#{path}: #{:file.format_error(reason)}"
end
