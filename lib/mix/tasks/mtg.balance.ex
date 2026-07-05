defmodule Mix.Tasks.Mtg.Balance do
  @shortdoc "Report how evenly a cube supports its archetypes"

  @moduledoc """
  Assess a cube's archetype balance: which archetypes have enough playables to
  draft, which are thin, which are over-supplied, and which lack signposts.

      mix mtg.balance on_a_stick

  Requires the archetypes to be discovered first (`mix mtg.assign <cube>`).
  """

  use Mix.Task

  alias DeckManager.Archetypes.Balance
  alias DeckManager.{Cards, Scryfall}

  @impl Mix.Task
  def run([list | _]) do
    Mix.Task.run("app.start")
    cache = "data/archetypes/#{list}.json"

    if File.exists?(cache) do
      cards = load_cards(list)
      archetypes = cache |> File.read!() |> Jason.decode!() |> Map.fetch!("archetypes")
      print(list, Balance.report(cards, archetypes))
    else
      Mix.shell().error("No archetypes cached for #{list}. Run: mix mtg.assign #{list}")
    end
  end

  def run(_), do: Mix.shell().error("usage: mix mtg.balance <cube>")

  defp load_cards(list) do
    if File.exists?("decks/#{list}.txt"), do: Cards.for_list(list), else: Scryfall.set_cards(list)
  end

  defp print(list, report) do
    max = report.archetypes |> Enum.map(& &1.members) |> Enum.max(fn -> 1 end)

    Mix.shell().info(
      "\nBALANCE — #{list}  (median supply: #{report.median} cards/archetype)\n" <>
        String.duplicate("─", 60)
    )

    report.archetypes
    |> Enum.sort_by(& &1.members, :desc)
    |> Enum.each(fn a ->
      Mix.shell().info(
        "#{String.pad_trailing(a.colors, 5)} #{bar(a.members, max)} " <>
          "#{String.pad_leading(to_string(a.members), 3)}  " <>
          "#{verdict(a)}  #{a.name}"
      )
    end)

    thin = Enum.filter(report.archetypes, &(&1.health == :thin))
    deep = Enum.filter(report.archetypes, &(&1.health == :deep))
    weak = Enum.filter(report.archetypes, & &1.low_signposts?)

    Mix.shell().info(String.duplicate("─", 60))
    summarize("Thin (needs more playables)", thin)
    summarize("Over-supplied", deep)
    summarize("Few signposts (needs gold direction)", weak)

    Mix.shell().info("\n#{report.total} cards · #{report.flex} flex · #{report.fixing} fixing")
  end

  # 20-cell bar scaled to the deepest archetype.
  defp bar(n, max) do
    filled = round(n / max * 20)
    "│" <> String.duplicate("█", filled) <> String.duplicate("·", 20 - filled) <> "│"
  end

  defp verdict(%{health: :thin}), do: "THIN "
  defp verdict(%{health: :deep}), do: "DEEP "
  defp verdict(_), do: "  ·  "

  defp summarize(_label, []), do: :ok

  defp summarize(label, list) do
    names = Enum.map_join(list, ", ", fn a -> "#{a.colors} #{a.name}" end)
    Mix.shell().info("#{label}: #{names}")
  end
end
