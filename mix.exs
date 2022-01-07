defmodule EctoMnesia.MixProject do
  use Mix.Project

  def project do
    [
      name: "Ecto3 Mnesia",
      app: :ecto3_mnesia,
      version: "0.3.0",
      elixir: "~> 1.9",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      dialyzer: [
        plt_add_apps: [:mnesia, :mix]
      ],
      source_url: "https://gitlab.com/patatoid/ecto3_mnesia",
      description: description(),
      package: package(),
      docs: [
        main: "readme",
        extras: ["README.md"]
      ],
      elixirc_paths: elixirc_paths(Mix.env()),
      consolidate_protocols: Mix.env() != :test,
      aliases: aliases()
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(:dev), do: ["lib", "lib_support"]
  defp elixirc_paths(:prod), do: ["lib"]

  def application do
    [
      extra_applications: [:logger, :mnesia]
    ]
  end

  defp deps do
    [
      {:ecto, "~> 3.0"},
      {:ex_doc, "~> 0.21", only: :dev, runtime: false},
      {:dialyxir, "~> 1.0.0-rc.7", only: [:dev], runtime: false},
      # Benchmarks
      {:benchee, "~> 1.0", only: :dev},
      {:benchee_html, "~> 1.0", only: :dev},
      {:benchee_json, "~> 1.0", only: :dev}
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

  defp aliases do
    [
      benchmark: "run benchmarks/get.exs",
      profile: "run benchmarks/prof.exs"
    ]
  end
end
