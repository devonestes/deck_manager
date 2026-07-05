defmodule Mix.Tasks.Mtg.Suggest do
  @shortdoc "Suggest owned cards to add to a cube's thin archetypes"

  @moduledoc """
  For each under-supplied archetype in a cube, suggest cards you own (from
  `decks/collection.csv`) but haven't cubed yet that would strengthen it.

      mix mtg.suggest on_a_stick          # suggest for the thin archetypes
      mix mtg.suggest on_a_stick --all    # suggest for every archetype
      mix mtg.suggest on_a_stick RG       # suggest for one archetype by colors

  Candidates are scored the same way live cube cards are (`Assignment`), so a
  suggestion is a real signpost/synergy fit, not just a color-legal card.
  Requires the archetypes to be discovered first (`mix mtg.assign <cube>`).
  """

  use Mix.Task

  alias DeckManager.Archetypes.{Assignment, Balance, Gallery}
  alias DeckManager.{Cards, Collection, Scryfall}

  @per_archetype 12
  @out_dir "reports"

  @impl Mix.Task
  def run(args) do
    {opts, rest, _} = OptionParser.parse(args, strict: [all: :boolean])

    case rest do
      [list | filter] ->
        Mix.Task.run("app.start")
        run_list(list, Keyword.get(opts, :all, false), List.first(filter))

      _ ->
        Mix.shell().error("usage: mix mtg.suggest <cube> [colors] [--all]")
    end
  end

  defp run_list(list, all?, colors_filter) do
    cache = "data/archetypes/#{list}.json"

    if not File.exists?(cache) do
      Mix.shell().error("No archetypes cached for #{list}. Run: mix mtg.assign #{list}")
    else
      cube =
        if File.exists?("decks/#{list}.txt"),
          do: Cards.for_list(list),
          else: Scryfall.set_cards(list)

      archetypes = cache |> File.read!() |> Jason.decode!() |> Map.fetch!("archetypes")

      targets = target_archetypes(cube, archetypes, all?, colors_filter)

      if targets == [] do
        Mix.shell().info(
          "#{list} looks balanced — no thin archetypes. Use --all or name an archetype's colors to see suggestions anyway."
        )
      else
        suggest(list, cube, archetypes, targets)
      end
    end
  end

  # Which archetypes to suggest for: an explicit colors filter, or every
  # archetype under --all, else just the ones balance flags as thin.
  defp target_archetypes(cube, archetypes, all?, colors_filter) do
    cond do
      colors_filter ->
        Enum.filter(archetypes, &(&1["colors"] == colors_filter))

      all? ->
        archetypes

      true ->
        thin =
          cube
          |> Balance.report(archetypes)
          |> Map.fetch!(:archetypes)
          |> Enum.filter(&(&1.health == :thin))
          |> MapSet.new(& &1.colors)

        Enum.filter(archetypes, &MapSet.member?(thin, &1["colors"]))
    end
  end

  defp suggest(list, cube, archetypes, targets) do
    cube_names = MapSet.new(cube, & &1.name)
    candidates = candidate_cards(cube_names)

    # Score candidates alongside the cube so the detector/theme context is the
    # cube's, then read off each target archetype's non-cube members.
    supply =
      Assignment.by_archetype(Assignment.assign(cube ++ candidates, archetypes), archetypes)

    by_name = Map.new(supply, fn {arch, members} -> {arch["archetype"], members} end)

    sections = Enum.map(targets, fn arch -> {arch, adds(by_name, arch, cube_names)} end)

    print(list, length(candidates), sections)
    write_html(list, sections)
  end

  # Drawing from a whole collection, a mere color-legal gold card is not a
  # suggestion — require a real *core* theme match (evergreen combat words don't
  # count), and rank by how well it fits (a gold card breaks ties, being
  # committed to the pair).
  defp adds(by_name, arch, cube_names) do
    by_name
    |> Map.get(arch["archetype"], [])
    |> Enum.reject(&MapSet.member?(cube_names, &1.card.name))
    |> Enum.reject(&(&1.core == []))
    |> Enum.sort_by(fn m -> {length(m.core), m.role == :signpost} end, :desc)
    |> Enum.take(@per_archetype)
  end

  defp print(list, candidate_count, sections) do
    Mix.shell().info(
      "\nADD SUGGESTIONS — #{list}  (#{candidate_count} owned cards not yet cubed)\n" <>
        String.duplicate("─", 60)
    )

    Enum.each(sections, fn {arch, adds} ->
      Mix.shell().info(
        "\n#{arch["colors"]} · #{arch["archetype"]} — top #{length(adds)} owned adds:"
      )

      if adds == [] do
        Mix.shell().info("  (nothing owned fits)")
      else
        Enum.each(adds, fn m ->
          star = if m.role == :signpost, do: "★ ", else: "  "
          Mix.shell().info("  #{star}#{m.card.name}  [#{Enum.join(m.matched, ", ")}]")
        end)
      end
    end)
  end

  defp write_html(list, sections) do
    File.mkdir_p!(@out_dir)
    path = Path.join(@out_dir, "#{list}_suggestions.html")
    File.write!(path, Gallery.suggestions_html(list, sections))
    Mix.shell().info("\nHTML: #{path}  —  open #{path}")
  end

  # Owned cards resolvable in the oracle data, excluding what's already cubed and
  # basic lands (never a meaningful "add").
  defp candidate_cards(cube_names) do
    index = Scryfall.by_name()

    Collection.owned_names()
    |> Enum.reject(&MapSet.member?(cube_names, &1))
    |> Enum.map(&Map.get(index, &1))
    |> Enum.reject(&is_nil/1)
    |> Enum.reject(fn c -> String.contains?(c.type_line || "", "Basic Land") end)
  end
end
