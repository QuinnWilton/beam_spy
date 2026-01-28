defmodule BeamSpy.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/quintusdev/beam_spy"

  def project do
    [
      app: :beam_spy,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      compilers: [:gleam] ++ Mix.compilers(),
      deps: deps(),
      escript: escript(),
      releases: releases(),
      aliases: aliases(),
      erlc_paths: ["src"],
      erlc_include_path: "src",

      # Test
      test_ignore_filters: [~r{test/fixtures/}, ~r{test/support/}],

      # Hex
      description: "A comprehensive BEAM file analysis tool",
      package: package(),
      source_url: @source_url,

      # Docs
      name: "BeamSpy",
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {BeamSpy.Application, []}
    ]
  end

  defp deps do
    [
      # CLI parsing
      {:optimus, "~> 0.5"},

      # JSON encoding
      {:jason, "~> 1.4"},

      # TOML parsing for themes
      {:toml, "~> 0.7"},

      # Table formatting
      {:table_rex, "~> 4.0"},

      # Binary distribution
      {:burrito, "~> 1.0"},

      # Dev/Test dependencies
      {:stream_data, "~> 1.0", only: [:test, :dev]},
      {:mneme, "~> 0.10", only: [:test, :dev]},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},

      # Test fixtures for other BEAM languages
      {:mix_gleam, "~> 0.6", only: :test, runtime: false},
      {:gleam_stdlib, "~> 0.68", only: :test, runtime: false, app: false}
    ]
  end

  defp releases do
    [
      beam_spy: [
        steps: [:assemble, &Burrito.wrap/1],
        burrito: [
          targets: [
            macos_arm64: [os: :darwin, cpu: :aarch64],
            macos_x86_64: [os: :darwin, cpu: :x86_64],
            linux_x86_64: [os: :linux, cpu: :x86_64],
            linux_arm64: [os: :linux, cpu: :aarch64],
            windows_x86_64: [os: :windows, cpu: :x86_64]
          ]
        ]
      ]
    ]
  end

  defp escript do
    [
      main_module: BeamSpy.CLI,
      name: "beam_spy"
    ]
  end

  defp aliases do
    [
      "test.fixtures": ["run test/support/build_fixtures.exs"]
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib priv mix.exs README.md LICENSE CHANGELOG.md)
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "CHANGELOG.md"],
      source_ref: "v#{@version}"
    ]
  end
end
