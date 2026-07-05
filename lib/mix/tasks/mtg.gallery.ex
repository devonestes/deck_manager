defmodule Mix.Tasks.Mtg.Gallery do
  @shortdoc "Render a pool's archetype assignment as an HTML card gallery"

  @moduledoc """
  Build a browsable HTML gallery of a pool's cards grouped by archetype, with
  card images, signpost highlights, and the matched mechanics under each card.

      mix mtg.gallery sos
      mix mtg.gallery on_a_stick

  Writes `reports/<pool>.html`. Requires the archetypes to be discovered first
  (run `mix mtg.assign <pool>`, which caches them). Open the file in a browser;
  images load from Scryfall, so you need to be online.
  """

  use Mix.Task

  alias DeckManager.Archetypes.Gallery
  alias DeckManager.{Cards, Scryfall}

  @out_dir "reports"

  @impl Mix.Task
  def run([list | _]) do
    Mix.Task.run("app.start")
    cache = "data/archetypes/#{list}.json"

    if File.exists?(cache) do
      cards = load_cards(list)
      archetypes = cache |> File.read!() |> Jason.decode!() |> Map.fetch!("archetypes")

      File.mkdir_p!(@out_dir)
      path = Path.join(@out_dir, "#{list}.html")
      File.write!(path, Gallery.html(list, cards, archetypes))

      Mix.shell().info("Wrote #{path} (#{length(cards)} cards). Open it: open #{path}")
    else
      Mix.shell().error("No archetypes cached for #{list}. Run: mix mtg.assign #{list}")
    end
  end

  def run(_), do: Mix.shell().error("usage: mix mtg.gallery <pool>")

  defp load_cards(list) do
    if File.exists?("decks/#{list}.txt"), do: Cards.for_list(list), else: Scryfall.set_cards(list)
  end
end
