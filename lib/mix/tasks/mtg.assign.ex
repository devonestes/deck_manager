defmodule Mix.Tasks.Mtg.Assign do
  @shortdoc "Assign each card in a pool to its archetype(s)"

  @moduledoc """
  Place every card in a cube or set into the archetypes it belongs to, as a
  signpost, a synergy piece, or an incidental role-player.

      mix mtg.assign on_a_stick
      mix mtg.assign on_a_stick --rediscover   # ignore the cache, re-run synthesis

  The archetype list comes from `Discovery.discover/2` (a frontier-model call),
  cached to `data/archetypes/<list>.json` so it's paid for once. Prints the
  per-archetype supply (signposts first) and the flexible role-player pool.
  """

  use Mix.Task

  alias DeckManager.Archetypes.{Assignment, Discovery}
  alias DeckManager.{Cards, Scryfall}

  @impl Mix.Task
  def run(args) do
    {opts, rest, _} = OptionParser.parse(args, strict: [rediscover: :boolean])

    case rest do
      [list | _] ->
        Mix.Task.run("app.start")
        run_list(list, Keyword.get(opts, :rediscover, false))

      _ ->
        Mix.shell().error("usage: mix mtg.assign <list-name> [--rediscover]")
    end
  end

  defp run_list(list, rediscover?) do
    cards = load_cards(list)

    case archetypes(list, cards, rediscover?) do
      {:ok, archetypes} ->
        assignments = Assignment.assign(cards, archetypes)
        print_supply(Assignment.by_archetype(assignments, archetypes))
        print_flex(Assignment.flex_cards(assignments))

        Mix.shell().info("\n#{length(cards)} cards across #{length(archetypes)} archetypes.")

      {:error, reason} ->
        Mix.shell().error("Could not discover archetypes: #{inspect(reason)}")
    end
  end

  # A pool is either a saved decklist/cube under `decks/` or, failing that, a
  # Scryfall set code (e.g. `snc`) fetched live for one-off set analysis.
  defp load_cards(list) do
    if File.exists?("decks/#{list}.txt") do
      Cards.for_list(list)
    else
      Scryfall.set_cards(list)
    end
  end

  @cache_dir "data/archetypes"

  # Cached frontier synthesis, or run it once and cache. The archetype set for a
  # pool is stable until the pool changes, so this shouldn't re-run each time.
  defp archetypes(list, cards, rediscover?) do
    path = Path.join(@cache_dir, "#{list}.json")

    if not rediscover? and File.exists?(path) do
      {:ok, path |> File.read!() |> Jason.decode!() |> Map.fetch!("archetypes")}
    else
      Mix.shell().info("Discovering archetypes in #{list} (#{length(cards)} cards)…\n")

      with {:ok, %{"archetypes" => archetypes} = result} <- discover_valid(cards) do
        File.mkdir_p!(@cache_dir)
        File.write!(path, Jason.encode!(result, pretty: true))
        {:ok, archetypes}
      end
    end
  end

  # The frontier call occasionally returns a degenerate stub (one archetype, no
  # mechanics) when adaptive thinking runs long on a large set. That's never a
  # real answer for a 100+ card pool, and caching it silently poisons every later
  # run — so validate and retry once rather than persist garbage.
  defp discover_valid(cards) do
    case Discovery.discover(cards) do
      {:ok, %{"archetypes" => archetypes}} = ok when length(archetypes) >= 3 ->
        ok

      {:ok, _degenerate} ->
        Mix.shell().info("  (discovery returned too few archetypes; retrying once…)\n")
        Discovery.discover(cards)

      error ->
        error
    end
  end

  defp print_supply(supply) do
    Enum.each(supply, fn {arch, members} ->
      {signposts, synergy} = Enum.split_with(members, &(&1.role == :signpost))

      Mix.shell().info(
        "\n#{arch["colors"]} · #{arch["archetype"]} " <>
          "(#{arch["tier"]}) — #{length(members)} cards"
      )

      Enum.each(signposts, fn m ->
        Mix.shell().info("    ★ #{m.card.name}#{mechanics(m.matched)}")
      end)

      synergy
      |> Enum.take(20)
      |> Enum.each(fn m ->
        Mix.shell().info("      #{m.card.name}#{mechanics(m.matched)}")
      end)

      extra = length(synergy) - 20
      if extra > 0, do: Mix.shell().info("      …and #{extra} more")
    end)
  end

  defp print_flex([]), do: :ok

  defp print_flex(flex) do
    {lands, nonland} =
      Enum.split_with(flex, &String.contains?(&1.card.type_line || "", "Land"))

    if nonland != [] do
      Mix.shell().info("\nFLEX / ROLE-PLAYERS (#{length(nonland)} cards, no single home):")
      print_columns(nonland)
    end

    if lands != [] do
      Mix.shell().info("\nFIXING / LANDS (#{length(lands)}):")
      print_columns(lands)
    end
  end

  defp print_columns(cards) do
    cards
    |> Enum.map(& &1.card.name)
    |> Enum.sort()
    |> Enum.chunk_every(3)
    |> Enum.each(fn row -> Mix.shell().info("  " <> Enum.join(row, " · ")) end)
  end

  defp mechanics([]), do: ""
  defp mechanics(list), do: "  [" <> Enum.join(list, ", ") <> "]"
end
