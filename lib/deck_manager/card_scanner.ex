defmodule DeckManager.CardScanner do
  @moduledoc """
  Turns a photo of Magic cards into Moxfield-importable collection entries.

  Every real Magic card prints its collector number and set code in the bottom-
  left corner. This module hands the image to a vision model to read those two
  identifiers off each visible card, then confirms each one against Scryfall's
  per-printing endpoint to recover the canonical name — so the CSV never depends
  on the model guessing a card's name, only on it reading the small print.

  Usage:

      DeckManager.CardScanner.to_csv("https://example.com/cards.jpg")
      DeckManager.CardScanner.to_csv(["front.jpg", "back.jpg"])
      DeckManager.CardScanner.to_csv("photos/2026-08-01")

  Returns `{:ok, csv_string, warnings}` or `{:error, reason}`.
  """

  alias DeckManager.{Anthropic, Moxfield, Scryfall}

  # Photos are scanned one request each, so this is how many are in flight at
  # once. Kept low because each request carries a full-resolution image and the
  # account's rate limit is measured in input tokens per minute, not requests.
  @max_concurrency 4

  @image_extensions ~w(.jpg .jpeg .png .gif .webp)

  @schema %{
    type: "object",
    properties: %{
      cards: %{
        type: "array",
        items: %{
          type: "object",
          properties: %{
            set: %{
              type: "string",
              description:
                "The set code printed in the card's bottom-left corner (e.g. \"EOE\", \"MH3\"), lowercased if you like — 3-4 letters/digits."
            },
            collector_number: %{
              type: "string",
              description:
                "The collector number printed next to the set code (e.g. \"42\", \"0123\", \"112a\"). Digits only unless a letter suffix is clearly printed. Drop any leading zeros is fine."
            },
            quantity: %{
              type: "integer",
              description: "How many copies of this exact card are visible. Usually 1."
            },
            foil: %{
              type: "boolean",
              description:
                "True only if the card is unmistakably foil (rainbow sheen). Otherwise false."
            },
            name: %{
              type: "string",
              description: "The card's printed name, as read — used only as a fallback label."
            }
          },
          required: ["set", "collector_number", "quantity", "foil", "name"],
          additionalProperties: false
        }
      }
    },
    required: ["cards"],
    additionalProperties: false
  }

  @prompt """
  You are reading a photograph of one or more Magic: The Gathering cards laid out
  so their bottom-left corners are legible. For every distinct card visible,
  report the SET CODE and COLLECTOR NUMBER printed in the bottom-left corner.

  Rules:
  - The bottom-left of a modern card shows: collector number, then the set code,
    then the language (e.g. "0042/0281  EOE • EN"). Read the collector number and
    the set code. The set code is the 3-4 character group (letters/digits).
  - If several identical cards are stacked or repeated, set `quantity` to the
    count and report the card once.
  - Only report cards where you can actually read the set + collector number. If a
    card's corner is obscured, skip it rather than guessing.
  - Report the set code exactly as printed; do not translate promo/variant codes.
  Return the structured list of cards.
  """

  @doc """
  Full pipeline: read the image(s), resolve every card against Scryfall, and
  return `{:ok, csv, warnings}` where `csv` is Moxfield import text and
  `warnings` is a list of human-readable strings for cards that couldn't be
  read or resolved.

  A directory reference is expanded into the images inside it, and every image
  gets its own vision request rather than being stacked into one — a folder of
  photos is more than a single request can read accurately, and per-request
  failures then only cost that one photo. Results are pooled before resolution,
  so a printing that appears in two photos merges into one entry with a count of
  two. Only a run where every image failed returns `{:error, reason}`.

  Options: `:max_concurrency` (how many images to scan at once, default
  #{@max_concurrency}) and `:on_image`, a two-arity function called with the
  reference and its `{:ok, cards}` / `{:error, reason}` result as each image
  finishes, for progress reporting. Anything else is passed to `scan/2`.
  """
  def to_csv(image_refs, opts \\ []) do
    {max_concurrency, opts} = Keyword.pop(opts, :max_concurrency)
    {on_image, opts} = Keyword.pop(opts, :on_image, fn _ref, _result -> :ok end)

    refs = expand_refs(image_refs)
    {extracted, failures} = scan_each(refs, max_concurrency || @max_concurrency, on_image, opts)

    if refs != [] and length(failures) == length(refs) do
      {_ref, reason} = hd(failures)
      {:error, reason}
    else
      {entries, warnings} = resolve(extracted)
      {:ok, Moxfield.to_csv(entries), Enum.map(failures, &unreadable/1) ++ warnings}
    end
  end

  @doc """
  Expand image references, replacing any local directory with the image files
  directly inside it (sorted by name, not recursive). URLs, plain file paths and
  `{media_type, base64}` tuples pass through untouched.
  """
  def expand_refs(image_refs) do
    image_refs |> List.wrap() |> Enum.flat_map(&expand_ref/1)
  end

  defp expand_ref("http://" <> _ = url), do: [url]
  defp expand_ref("https://" <> _ = url), do: [url]

  defp expand_ref(path) when is_binary(path) do
    if File.dir?(Path.expand(path)) do
      path
      |> Path.expand()
      |> File.ls!()
      |> Enum.filter(&image?/1)
      |> Enum.sort()
      |> Enum.map(&Path.join(path, &1))
    else
      [path]
    end
  end

  defp expand_ref(other), do: [other]

  defp image?(name),
    do: name |> Path.extname() |> String.downcase() |> Kernel.in(@image_extensions)

  defp scan_each(refs, max_concurrency, on_image, opts) do
    refs
    |> Task.async_stream(
      fn ref ->
        result = scan(ref, opts)
        on_image.(ref, result)
        {ref, result}
      end,
      max_concurrency: max_concurrency,
      timeout: :infinity,
      ordered: true
    )
    |> Enum.reduce({[], []}, fn {:ok, {ref, result}}, {cards, failures} ->
      case result do
        {:ok, found} -> {cards ++ found, failures}
        {:error, reason} -> {cards, failures ++ [{ref, reason}]}
      end
    end)
  end

  defp unreadable({ref, reason}), do: "Could not scan #{ref} — #{inspect(reason)}"

  @doc """
  Just the vision step: returns `{:ok, [%{set, collector_number, quantity, foil,
  name}]}` read off the image(s), or `{:error, reason}`.
  """
  def scan(image_refs, opts \\ []) do
    with {:ok, images} <- image_blocks(List.wrap(image_refs)),
         {:ok, text} <- Anthropic.generate(@prompt, [images: images, format: @schema] ++ opts),
         {:ok, %{"cards" => cards}} <- decode(text) do
      {:ok, cards}
    end
  end

  defp image_blocks(refs) do
    Enum.reduce_while(refs, {:ok, []}, fn ref, {:ok, acc} ->
      case Anthropic.image_block(ref) do
        {:ok, block} -> {:cont, {:ok, [block | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, blocks} -> {:ok, Enum.reverse(blocks)}
      error -> error
    end
  end

  defp decode(text) do
    case Jason.decode(text) do
      {:ok, map} -> {:ok, map}
      {:error, _} -> {:error, {:bad_vision_json, text}}
    end
  end

  # Look each extracted card up on Scryfall, then merge duplicates (same set +
  # collector number + foil) into a single entry with summed counts.
  defp resolve(extracted) do
    {entries, warnings} =
      Enum.reduce(extracted, {[], []}, fn card, {entries, warnings} ->
        case Scryfall.card_by_set_number(card["set"], card["collector_number"]) do
          {:ok, printing} ->
            {[entry(card, printing) | entries], warnings}

          {:error, _} ->
            {entries, [warn(card) | warnings]}
        end
      end)

    {entries |> Enum.reverse() |> merge(), Enum.reverse(warnings)}
  end

  defp entry(card, printing) do
    %{
      count: max(card["quantity"] || 1, 1),
      name: printing["name"],
      edition: printing["set"],
      collector_number: printing["collector_number"],
      foil: card["foil"] == true
    }
  end

  defp merge(entries) do
    entries
    |> Enum.group_by(fn e -> {e.edition, e.collector_number, e.foil} end)
    |> Enum.map(fn {_key, group} ->
      total = group |> Enum.map(& &1.count) |> Enum.sum()
      %{hd(group) | count: total}
    end)
    |> Enum.sort_by(& &1.name)
  end

  defp warn(card) do
    "Could not resolve #{inspect(card["name"])} — set #{inspect(card["set"])}, number #{inspect(card["collector_number"])}"
  end
end
