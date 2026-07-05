defmodule DeckManager.Cards do
  @moduledoc """
  The card knowledge base: Scryfall's structured data joined with the functional
  tags from the local tagger. Everything downstream — archetype analysis, the
  draft predictor's features, the commander builder — reads cards from here, so
  the join lives in one place.
  """

  alias DeckManager.{Card, Pool, Scryfall, Tagger}

  @doc "All cards, each with `:tags` populated where we've tagged them."
  def all(opts \\ []) do
    tags = Tagger.load_tags()
    opts |> Scryfall.oracle_cards() |> Enum.map(&put_tags(&1, tags))
  end

  @doc "The `%Card{}` structs for the cards in a named list under `decks/` (with tags)."
  def for_list(list_name, opts \\ []) do
    tags = Tagger.load_tags()
    index = Scryfall.by_name(opts)

    list_name
    |> Pool.card_names()
    |> Enum.map(&Map.get(index, &1))
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&put_tags(&1, tags))
  end

  @doc "Names in a list that Scryfall didn't match — surfaces stale or renamed cards."
  def missing_from_list(list_name, opts \\ []) do
    index = Scryfall.by_name(opts)
    list_name |> Pool.card_names() |> Enum.reject(&Map.has_key?(index, &1))
  end

  defp put_tags(%Card{} = card, tags), do: %{card | tags: Map.get(tags, card.name)}
end
