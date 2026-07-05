defmodule DeckManager.Collection do
  @moduledoc """
  Reads the owned-card collection exported as `decks/collection.csv` (a standard
  quoted CSV with a `Name` column — the format Moxfield/Archidekt/etc. produce).

  This is the pool of cards available to *add* to a cube, so cube-balance
  suggestions draw candidates from here.
  """

  @path "decks/collection.csv"

  @doc "Unique owned card names, normalized to Scryfall's `//` double-faced form."
  def owned_names(path \\ @path) do
    path
    |> File.stream!()
    |> CSV.decode(headers: true)
    |> Enum.flat_map(fn
      {:ok, %{"Name" => name}} when is_binary(name) and name != "" -> [normalize(name)]
      _ -> []
    end)
    |> Enum.uniq()
  end

  # Exports write double-faced cards as "Front / Back"; Scryfall uses "Front // Back".
  defp normalize(name), do: String.replace(name, " / ", " // ")
end
