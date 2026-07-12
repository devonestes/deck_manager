defmodule DeckManager.Moxfield do
  @moduledoc """
  Renders collection entries as a Moxfield import CSV.

  The column layout mirrors Moxfield's own collection *export* (the format it
  round-trips on import), so a produced file drops straight into
  Moxfield → Collection → Import. Moxfield matches a row to a printing by
  `Name` + `Edition` + `Collector Number`, so those three are what must be right;
  the rest carry sensible defaults.
  """

  @headers ~w(Count) ++
             ["Tradelist Count", "Name", "Edition", "Condition", "Language", "Foil", "Tags"] ++
             ["Last Modified", "Collector Number", "Alter", "Proxy", "Purchase Price"]

  @doc """
  Build the CSV text from a list of entry maps. Each entry:

    * `:count` (default 1), `:name`, `:edition` (set code), `:collector_number`
    * optional `:foil` (boolean), `:condition` (default "Near Mint"),
      `:language` (default "English"), `:tags`

  """
  def to_csv(entries) do
    rows = Enum.map(entries, &row/1)
    [@headers | rows] |> Enum.map_join("\n", &encode_row/1)
  end

  defp row(entry) do
    [
      to_string(Map.get(entry, :count, 1)),
      to_string(Map.get(entry, :count, 1)),
      Map.get(entry, :name, ""),
      Map.get(entry, :edition, ""),
      Map.get(entry, :condition, "Near Mint"),
      Map.get(entry, :language, "English"),
      if(Map.get(entry, :foil, false), do: "foil", else: ""),
      Map.get(entry, :tags, ""),
      "",
      to_string(Map.get(entry, :collector_number, "")),
      "False",
      "False",
      ""
    ]
  end

  # Quote every field and double any embedded quotes, matching Moxfield's export.
  defp encode_row(fields), do: Enum.map_join(fields, ",", &quote_field/1)

  defp quote_field(value) do
    escaped = value |> to_string() |> String.replace("\"", "\"\"")
    "\"" <> escaped <> "\""
  end
end
