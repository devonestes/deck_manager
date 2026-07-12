defmodule DeckManager.Scryfall do
  @moduledoc """
  Fetches and caches Scryfall's `oracle_cards` bulk export (one entry per unique
  card). Each entry is trimmed to the handful of fields we use before caching, so
  the ~100 MB download becomes a small local file we can reload instantly.

  Refresh with `oracle_cards(force: true)` (or delete the cache file) when a new
  set releases.
  """

  alias DeckManager.Card

  @bulk_index "https://api.scryfall.com/bulk-data/oracle_cards"
  @cache_path "data/scryfall/oracle_cards.json"

  # Scryfall rejects requests without an explicit User-Agent and Accept header.
  @headers [
    {"user-agent", "deck_manager/0.1 (mtg card analysis)"},
    {"accept", "application/json"}
  ]

  # Layouts that aren't real, draftable/playable cards.
  @skip_layouts ~w(token double_faced_token emblem art_series scheme planar vanguard)

  @fields ~w(name oracle_text type_line mana_cost cmc colors color_identity
             power toughness rarity edhrec_rank set layout keywords card_faces
             image_uris)

  @doc "All playable cards as `%Card{}` structs, using the disk cache when present."
  def oracle_cards(opts \\ []) do
    if not Keyword.get(opts, :force, false) and File.exists?(@cache_path) do
      @cache_path |> File.read!() |> Jason.decode!() |> Enum.map(&Card.from_scryfall/1)
    else
      fetch_and_cache()
    end
  end

  @doc "Map of card name => `%Card{}`."
  def by_name(opts \\ []) do
    opts |> oracle_cards() |> Map.new(fn card -> {card.name, card} end)
  end

  @card_url "https://api.scryfall.com/cards"

  @doc """
  Look up one exact printing by its set code and collector number
  (e.g. "eoe", "42"). Returns `{:ok, map}` with the raw Scryfall card (string
  keys — includes `"name"`, `"set"`, `"collector_number"`) or `{:error, reason}`.

  This is the identity Moxfield imports on, so we hit Scryfall's per-printing
  endpoint rather than the oracle bulk (which has no collector numbers).
  """
  def card_by_set_number(set, number) do
    set = set |> to_string() |> String.trim() |> String.downcase()
    number = number |> to_string() |> String.trim()
    url = "#{@card_url}/#{URI.encode(set)}/#{URI.encode(number)}"

    case Req.get(url, headers: @headers) do
      {:ok, %{status: 200, body: %{} = card}} -> {:ok, card}
      {:ok, %{status: 404}} -> {:error, {:not_found, set, number}}
      {:ok, %{status: status, body: body}} -> {:error, {:scryfall_status, status, body}}
      {:error, exception} -> {:error, {:scryfall, Exception.message(exception)}}
    end
  end

  @search_url "https://api.scryfall.com/cards/search"

  @doc """
  Fetch all unique cards in a set by its Scryfall set code (e.g. "msh") as
  `%Card{}` structs. Not cached — used for one-off analysis of a specific set.
  """
  def set_cards(code) do
    query = URI.encode_query(%{"q" => "e:#{code}", "unique" => "cards"})

    (@search_url <> "?" <> query)
    |> fetch_search([])
    |> Enum.reject(fn c -> c["layout"] in @skip_layouts end)
    |> Enum.map(&Card.from_scryfall/1)
  end

  # Scryfall search paginates at 175 cards/page; follow next_page, pausing
  # briefly between requests per their rate-limit guidance.
  defp fetch_search(url, acc) do
    body = url |> Req.get!(headers: @headers) |> Map.fetch!(:body)
    acc = acc ++ Map.get(body, "data", [])

    case body do
      %{"has_more" => true, "next_page" => next} ->
        :timer.sleep(100)
        fetch_search(next, acc)

      _ ->
        acc
    end
  end

  defp fetch_and_cache do
    download_uri =
      @bulk_index
      |> Req.get!(headers: @headers)
      |> Map.fetch!(:body)
      |> Map.fetch!("download_uri")

    trimmed =
      download_uri
      |> Req.get!(headers: @headers)
      |> Map.fetch!(:body)
      |> Enum.reject(fn c -> c["layout"] in @skip_layouts end)
      |> Enum.map(fn c -> Map.take(c, @fields) end)

    File.mkdir_p!(Path.dirname(@cache_path))
    File.write!(@cache_path, Jason.encode!(trimmed))

    Enum.map(trimmed, &Card.from_scryfall/1)
  end
end
