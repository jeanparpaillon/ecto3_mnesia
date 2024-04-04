defmodule EctoMnesia.MixProject do
  use Mix.Project

  def project do
    [
      name: "Ecto3 Mnesia",
      app: :ecto3_mnesia,
      version: "0.2.2",
      elixir: "~> 1.9",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      dialyzer: dialyzer(),
      source_url: "https://github.com/jeanparpaillon/ecto3_mnesia",
      description: description(),
      package: package(),
      docs: docs(),
      elixirc_paths: elixirc_paths(Mix.env()),
      consolidate_protocols: Mix.env() != :test,
      aliases: aliases()
    ]
  end

  def cli do
    [
      default_env: :dev,
      preferred_envs: [benchmark: :test]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support", "test/benchmark"]
  defp elixirc_paths(:dev), do: ["lib", "test/benchmark"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [
      extra_applications: [:logger, :mnesia]
    ]
  end

  defp deps do
    [
      {:ecto, ">= 3.0.0 and < 3.11.0"},
      {:credo, ">= 0.0.0"},
      {:ex_doc, "~> 0.21", only: [:dev], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
      # Benchmarks
      {:benchee, "~> 1.0", only: [:dev, :test]},
      {:benchee_html, "~> 1.0", only: [:dev, :test]},
      {:benchee_json, "~> 1.0", only: [:dev, :test]}
    ]
  end

  defp package do
    %{
      name: "ecto3_mnesia",
      licenses: ["MIT"],
      links: %{
        "Gitlab" => "https://gitlab.com/patatoid/ecto3_mnesia"
      }
    }
  end

  defp description do
    """
    Mnesia adapter for Ecto 3
    """
  end

  defp docs do
    [
      main: "readme",
      extras: [
        "README.md",
        "guides/migrate_to_03.md"
      ]
    ]
  end

  defp aliases do
    [
      profile: "run benchmarks/prof.exs"
    ]
  end

  defp dialyzer do
    [
      plt_add_apps: [:mnesia, :mix],
      plt_core_path: "priv/plts",
      plt_file: {:no_warn, "priv/plts/dialyzer.plt"}
    ]
  end
end
