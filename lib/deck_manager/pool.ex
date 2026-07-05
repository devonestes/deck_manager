defmodule DeckManager.Pool do
  @moduledoc """
  Reads a decklist / set / cube list in the `decks/*.txt` format
  (`<count> <name> (<SET>) <collector>`) into card entries.

  This is the input every analysis tool evaluates against: a card's value only
  means something in the context of its pool, so we always read the whole set or
  cube, never a card alone.
  """

  @line ~r/^(\d+)\s+(.+)\s+\(([^)]+)\)\s+(\S+)\s*$/

  @doc "Entries as `[%{name: String.t(), count: integer}]` for a named list under `decks/`."
  def read(name), do: read_path("decks/#{name}.txt")

  @doc "Same as `read/1` but for an explicit path."
  def read_path(path) do
    path
    |> File.read!()
    |> String.trim()
    |> String.split("\n", trim: true)
    |> Enum.map(&parse_line/1)
    |> Enum.reject(&is_nil/1)
  end

  @doc "Just the card names in a named list."
  def card_names(name), do: name |> read() |> Enum.map(& &1.name)

  defp parse_line(line) do
    case Regex.run(@line, line) do
      [_, count, name, _set, _collector] ->
        %{name: normalize(name), count: String.to_integer(count)}

      _ ->
        nil
    end
  end

  # Decklists write double-faced cards as "Front / Back"; Scryfall uses "Front // Back".
  defp normalize(name), do: String.replace(name, " / ", " // ")
end
