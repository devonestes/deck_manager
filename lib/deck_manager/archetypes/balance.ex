defmodule DeckManager.Archetypes.Balance do
  @moduledoc """
  Assesses how evenly a cube supports its archetypes.

  Draft health is about *relative* supply: an archetype isn't thin at some
  absolute card count, it's thin compared to the cube's other archetypes. So we
  measure each archetype's playable support (signpost + synergy members) against
  the median across all of them, and flag the ones a drafter would struggle to
  assemble (too few playables) or that are over-supplied at others' expense.

  Signpost density is tracked separately: an archetype can have plenty of
  playables but too few gold signposts to actually *point* drafters into it.
  """

  alias DeckManager.Archetypes.Assignment

  @thin 0.6
  @deep 1.4
  @min_signposts 2

  @doc """
  Balance report for a cube: per-archetype supply stats with a health verdict,
  plus the pool-level totals. Returns a map with `:archetypes`, `:median`,
  `:flex`, `:fixing`, `:total`.
  """
  def report(cards, archetypes) do
    assignments = Assignment.assign(cards, archetypes)
    supply = Assignment.by_archetype(assignments, archetypes)

    # The median is taken over the archetypes that are *meant* to be fully
    # draftable (primary/support). Fringe archetypes are deliberately niche, so
    # judging them against that median would wrongly flag them as thin.
    core_counts =
      for {arch, members} <- supply, arch["tier"] in ["primary", "support"], do: length(members)

    median = median(core_counts)

    stats =
      Enum.map(supply, fn {arch, members} ->
        n = length(members)
        tier = arch["tier"]
        signposts = Enum.count(members, &(&1.role == :signpost))

        %{
          colors: arch["colors"],
          name: arch["archetype"],
          tier: tier,
          members: n,
          signposts: signposts,
          health: health(n, median, tier),
          low_signposts?: tier != "fringe" and signposts < @min_signposts
        }
      end)

    {lands, nonland} = Enum.split_with(Assignment.flex_cards(assignments), &land?(&1.card))

    %{
      archetypes: stats,
      median: median,
      flex: length(nonland),
      fixing: length(lands),
      total: length(cards)
    }
  end

  # Fringe archetypes are niche by design; only primary/support are judged for
  # thin/deep supply against the core median.
  defp health(_n, _median, "fringe"), do: :niche
  defp health(_n, median, _tier) when median == 0, do: :healthy
  defp health(n, median, _tier) when n < median * @thin, do: :thin
  defp health(n, median, _tier) when n > median * @deep, do: :deep
  defp health(_n, _median, _tier), do: :healthy

  defp median([]), do: 0

  defp median(list) do
    sorted = Enum.sort(list)
    len = length(sorted)
    mid = div(len, 2)

    if rem(len, 2) == 1 do
      Enum.at(sorted, mid)
    else
      (Enum.at(sorted, mid - 1) + Enum.at(sorted, mid)) / 2
    end
  end

  defp land?(card), do: String.contains?(card.type_line || "", "Land")
end
