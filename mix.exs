defmodule Apalachex.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/kokjinsam/apalachex"

  def project do
    [
      app: :apalachex,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      description: "Safe, deterministic Apalache execution and artifact management for Elixir.",
      package: package(),
      docs: docs(),
      source_url: @source_url,
      homepage_url: @source_url,
      test_coverage: [summary: [threshold: 90]]
    ]
  end

  def application, do: []

  def cli, do: [preferred_envs: [check: :test]]

  defp deps do
    [
      {:code_style, "~> 0.1.1", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.38", only: :dev, runtime: false},
      {:styler, "~> 1.11", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      check: [
        "format --check-formatted",
        "compile --warnings-as-errors",
        "credo --strict",
        "dialyzer",
        "test"
      ]
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(.formatter.exs CHANGELOG.md LICENSE README.md lib mix.exs)
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "CHANGELOG.md", "LICENSE"],
      groups_for_modules: [
        "Public API": [
          Apalachex,
          Apalachex.Error,
          Apalachex.Plan,
          Apalachex.Result,
          Apalachex.RunDirectory,
          Apalachex.Spec,
          Apalachex.Spec.Error
        ]
      ]
    ]
  end
end
