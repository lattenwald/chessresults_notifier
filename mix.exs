defmodule ChessresultsNotifier.MixProject do
  use Mix.Project

  def project do
    [
      app: :chessresults_notifier,
      version: "0.1.0",
      elixir: "~> 1.13",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: releases()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {ChessresultsNotifier.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:httpoison, "~> 1.7"},
      {:floki, "~> 0.32.0"},
      {:nadia, "~> 0.7.0"},
      {:jason, "~> 1.1"},
      {:toml_config_provider, "~> 0.2.0"},
      {:rexbug, "~> 1.0"}
    ]
  end

  defp releases do
    [
      prod: [
        include_executables_for: [:unix],
        config_providers: [
          {TomlConfigProvider, "/app/config.toml"}
        ],
        steps: [:assemble, :tar],
        path: "/app/release"
      ]
    ]
  end

end
