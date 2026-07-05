defmodule DeckManager.Card do
  @moduledoc """
  A Magic card as the analysis tools need it: the structured fields Scryfall
  already gives us, plus the functional `tags` the local model extracts.

  Scryfall is the source of truth for everything mechanical (cost, colors,
  keywords, stats), so the model is only ever asked for semantics it has to read
  off the rules text — never for facts we can look up.
  """

  @enforce_keys [:name]
  defstruct [
    :name,
    :oracle_text,
    :type_line,
    :cmc,
    :colors,
    :color_identity,
    :power,
    :toughness,
    :rarity,
    :edhrec_rank,
    :set,
    :layout,
    :image,
    keywords: [],
    tags: nil
  ]

  @type t :: %__MODULE__{}

  @doc "Build a Card from a decoded Scryfall oracle-card map (string keys)."
  def from_scryfall(%{} = c) do
    %__MODULE__{
      name: c["name"],
      oracle_text: oracle_text(c),
      type_line: c["type_line"],
      cmc: c["cmc"],
      colors: c["colors"] || [],
      color_identity: c["color_identity"] || [],
      power: c["power"],
      toughness: c["toughness"],
      rarity: c["rarity"],
      edhrec_rank: c["edhrec_rank"],
      set: c["set"],
      layout: c["layout"],
      image: image_url(c),
      keywords: c["keywords"] || []
    }
  end

  # Normal-size card image. Single-faced cards carry it at the top level;
  # double-faced/split cards carry it per face, so fall back to the front face.
  defp image_url(%{"image_uris" => %{"normal" => url}}), do: url

  defp image_url(%{"card_faces" => [%{"image_uris" => %{"normal" => url}} | _]}), do: url

  defp image_url(_), do: nil

  # Split / transform / adventure / MDFC cards carry their rules text on the
  # faces, not the top level — stitch the faces so the model sees all of it.
  defp oracle_text(%{"oracle_text" => text}) when is_binary(text) and text != "", do: text

  defp oracle_text(%{"card_faces" => faces}) when is_list(faces) do
    faces
    |> Enum.map(fn face -> face["oracle_text"] end)
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join("\n//\n")
  end

  defp oracle_text(_), do: ""
end
