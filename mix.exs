defmodule DeckManager.MixProject do
  use Mix.Project

  def project do
    [
      app: :deck_manager,
      version: "0.1.0",
      elixir: "~> 1.13",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp aliases do
    [
      build: &build/1,
      download: &download/1
    ]
  end

  defp build([]) do
    Mix.Task.run("app.start")
    DeckManager.run()
  end

  defp build([deck]) do
    Mix.Task.run("app.start")
    DeckManager.run(deck)
  end

  defp download([]) do
    Mix.Task.run("app.start")
    DeckManager.download()
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:csv, "~> 3.0"},
      {:req, "~> 0.4.8"}
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
    ]
  end
end
