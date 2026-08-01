defmodule Mix.Tasks.Mtg.Import do
  @shortdoc "Scan photos of cards into a Moxfield import CSV"

  @default_out "reports/import.csv"

  @moduledoc """
  Read the set code + collector number off every card in a photo and write a
  Moxfield-importable CSV.

      mix mtg.import https://example.com/my_cards.jpg
      mix mtg.import path/to/photo.jpg
      mix mtg.import front.jpg back.jpg --out reports/new_cards.csv
      mix mtg.import photos/2026-08-01 --out reports/new_cards.csv

  Accepts one or more image references: http(s) URLs, local file paths, or a
  directory, which stands in for every image file directly inside it (not
  recursive). Each image is scanned on its own and the results are pooled into a
  single CSV, so a card photographed in two shots is counted twice.

  Cards are identified against Scryfall, so you need to be online. Any image that
  can't be scanned, and any card whose corner can't be read or matched, is
  printed as a warning and left out of the CSV.

  Options:

    * `--out FILE` — where to write the CSV (default `#{@default_out}`)
    * `--max-concurrency N` — how many images to scan at once (default 4)

  Requires an Anthropic API key (env `ANTHROPIC_API_KEY` or
  `~/.config/anthropic/token`). Import the result at Moxfield → Collection → Import.
  """

  use Mix.Task

  alias DeckManager.CardScanner

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")

    {opts, refs, _} =
      OptionParser.parse(argv, strict: [out: :string, max_concurrency: :integer])

    case CardScanner.expand_refs(refs) do
      [] when refs == [] ->
        Mix.shell().error(
          "usage: mix mtg.import <image-url-path-or-directory> [more...] [--out FILE]"
        )

      [] ->
        Mix.shell().error("No images found in #{Enum.join(refs, ", ")}")

      images ->
        import_cards(images, opts)
    end
  end

  defp import_cards(images, opts) do
    out = Keyword.get(opts, :out, @default_out)
    Mix.shell().info("Scanning #{length(images)} image(s) ...")

    scan_opts = [
      on_image: &report/2,
      max_concurrency: Keyword.get(opts, :max_concurrency)
    ]

    case CardScanner.to_csv(images, scan_opts) do
      {:ok, csv, warnings} ->
        File.mkdir_p!(Path.dirname(out))
        File.write!(out, csv)
        rows = csv |> String.split("\n") |> length() |> Kernel.-(1)
        Enum.each(warnings, &Mix.shell().error("  ! #{&1}"))

        Mix.shell().info(
          "Wrote #{out} (#{rows} cards). Import at Moxfield → Collection → Import."
        )

      {:error, reason} ->
        Mix.shell().error("Failed: #{inspect(reason)}")
    end
  end

  # Progress as each image lands. The reason for a failed scan is left to the
  # warning summary printed at the end, so a long run's progress stays scannable.
  defp report(ref, {:ok, cards}),
    do: Mix.shell().info("  ✓ #{label(ref)} — #{length(cards)} card(s)")

  defp report(ref, {:error, _reason}),
    do: Mix.shell().error("  ✗ #{label(ref)} — scan failed")

  defp label(ref) when is_binary(ref), do: Path.basename(ref)
  defp label(_ref), do: "image"
end
