defmodule Mix.Tasks.Mtg.Import do
  @shortdoc "Scan a photo of cards into a Moxfield import CSV"

  @moduledoc """
  Read the set code + collector number off every card in a photo and write a
  Moxfield-importable CSV.

      mix mtg.import https://example.com/my_cards.jpg
      mix mtg.import path/to/photo.jpg
      mix mtg.import front.jpg back.jpg --out reports/new_cards.csv

  Accepts one or more image references (http(s) URLs or local file paths). Cards
  are identified against Scryfall, so you need to be online. Any card whose
  corner can't be read or matched is printed as a warning and left out of the CSV.

  Requires an Anthropic API key (env `ANTHROPIC_API_KEY` or
  `~/.config/anthropic/token`). Import the result at Moxfield → Collection → Import.
  """

  use Mix.Task

  alias DeckManager.CardScanner

  @default_out "reports/import.csv"

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")
    {opts, images, _} = OptionParser.parse(argv, strict: [out: :string])

    case images do
      [] ->
        Mix.shell().error(
          "usage: mix mtg.import <image-url-or-path> [more images...] [--out FILE]"
        )

      refs ->
        out = Keyword.get(opts, :out, @default_out)
        import_cards(refs, out)
    end
  end

  defp import_cards(refs, out) do
    Mix.shell().info("Scanning #{Enum.join(refs, ", ")} ...")

    case CardScanner.to_csv(refs) do
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
end
