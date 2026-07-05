defmodule Mix.Tasks.Mtg.Archetypes do
  @shortdoc "Discover a pool's archetypes from its cards"

  @moduledoc """
  Analyze a cube or set list and discover its draft archetypes — the 10 color
  pairs plus any mono/multicolor build-arounds — from the cards alone.

      mix mtg.archetypes on_a_stick

  Prints the theme evidence, then the synthesized archetypes. Requires the cards
  to be tagged first (`mix mtg.tag <list>`) and the synthesis model pulled.
  """

  use Mix.Task

  alias DeckManager.Archetypes.Discovery
  alias DeckManager.Cards

  @impl Mix.Task
  def run([list | _]) do
    Mix.Task.run("app.start")
    cards = Cards.for_list(list)
    Mix.shell().info("Discovering archetypes in #{list} (#{length(cards)} cards)…\n")

    cards
    |> Discovery.assign()
    |> Enum.each(fn {pair, primary, themes} ->
      {name, sc} = primary || {"—", 0.0}

      also =
        themes
        |> Enum.reject(fn {n, _, _, _, _} -> n == name end)
        |> Enum.take(2)
        |> Enum.map_join(", ", fn {n, _, _, d, g} -> "#{n}(d=#{d}/gold=#{g})" end)

      Mix.shell().info(
        "  #{String.pad_trailing(pair, 4)} #{String.pad_trailing(name, 26)} #{sc}   also: #{also}"
      )
    end)
  end

  def run(_), do: Mix.shell().error("usage: mix mtg.archetypes <list-name>")
end
