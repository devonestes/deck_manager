defmodule DeckManager.Language do
  @moduledoc """
  Card languages, keyed by the code printed on the collector line.

  A modern card prints its language right after the set code ("FRA • DE"), and
  the same language goes by a different name in each place it has to travel:
  Scryfall's per-printing endpoint wants its own short code (`de`), and
  Moxfield's import wants the English name (`German`). A wrong language is a
  wrong printing to Moxfield, so this is not cosmetic.
  """

  # printed code => {Scryfall code, Moxfield name}
  @languages %{
    "EN" => {"en", "English"},
    "DE" => {"de", "German"},
    "FR" => {"fr", "French"},
    "IT" => {"it", "Italian"},
    "ES" => {"es", "Spanish"},
    "SP" => {"es", "Spanish"},
    "PT" => {"pt", "Portuguese"},
    "JP" => {"ja", "Japanese"},
    "JA" => {"ja", "Japanese"},
    "KO" => {"ko", "Korean"},
    "KR" => {"ko", "Korean"},
    "RU" => {"ru", "Russian"},
    "CS" => {"zhs", "Chinese Simplified"},
    "ZHS" => {"zhs", "Chinese Simplified"},
    "CT" => {"zht", "Chinese Traditional"},
    "ZHT" => {"zht", "Chinese Traditional"},
    "PH" => {"ph", "Phyrexian"}
  }

  @by_scryfall @languages
               |> Enum.map(fn {_printed, {scryfall, moxfield}} -> {scryfall, moxfield} end)
               |> Map.new()

  @doc """
  The Scryfall code for a printed language code ("DE" → "de"), or `nil` when
  the code is blank or unknown — the caller then looks the card up in English,
  which is what an unreadable language most likely was.
  """
  def scryfall_code(printed) when is_binary(printed) do
    case Map.get(@languages, printed |> String.trim() |> String.upcase()) do
      {scryfall, _moxfield} -> scryfall
      nil -> nil
    end
  end

  def scryfall_code(_printed), do: nil

  @doc "The Moxfield name for a Scryfall language code (\"de\" → \"German\"), English when unknown."
  def moxfield_name(scryfall) when is_binary(scryfall),
    do: Map.get(@by_scryfall, scryfall, "English")

  def moxfield_name(_scryfall), do: "English"
end
