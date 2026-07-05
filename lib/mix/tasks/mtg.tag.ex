defmodule Mix.Tasks.Mtg.Tag do
  @shortdoc "Tag cards' functions with the local model (Ollama/Qwen)"

  @moduledoc """
  Extract functional tags for cards with the local model, caching them for every
  other MTG analysis tool to read.

      mix mtg.tag              # every playable card in Scryfall's oracle set (~30k)
      mix mtg.tag on_a_stick   # only the cards in decks/on_a_stick.txt

  Resumable: only cards missing from `data/tags/tags.jsonl` are tagged, so you can
  stop and restart, or re-run after adding a set, without redoing work.

  Requires Ollama running locally (`localhost:11434`) with the model pulled.
  """

  use Mix.Task

  alias DeckManager.{Cards, Scryfall, Tagger}

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    cards =
      case args do
        [] ->
          Mix.shell().info("Loading all oracle cards from Scryfall…")
          Scryfall.oracle_cards()

        [list | _] ->
          Mix.shell().info("Loading cards from decks/#{list}.txt…")
          warn_missing(list)
          Cards.for_list(list)
      end

    Mix.shell().info("Tagging #{length(cards)} cards (already-tagged are skipped)…")
    result = Tagger.tag_all(cards)

    Mix.shell().info("""

    Done. tagged=#{result.tagged} failed=#{result.failed} skipped=#{result.skipped}
    Cache: data/tags/tags.jsonl
    """)
  end

  defp warn_missing(list) do
    case Cards.missing_from_list(list) do
      [] ->
        :ok

      missing ->
        Mix.shell().info("  (#{length(missing)} names not matched on Scryfall, skipping)")
    end
  end
end
