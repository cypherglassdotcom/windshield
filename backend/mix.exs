defmodule Windshield.Mixfile do
  use Mix.Project

  def project do
    [
      app: :windshield,
      version: "0.0.2",
      elixir: "~> 1.4",
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: [:phoenix, :gettext] ++ Mix.compilers(),
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Windshield.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix, "~> 1.3.0"},
      {:phoenix_pubsub, "~> 1.0"},
      {:gettext, "~> 0.11"},
      {:cowboy, "~> 1.0"},
      {:tesla, "~> 1.0.0-beta.1"},
      {:eosrpc, "~> 0.2.2-beta"},
      {:cors_plug, "~> 1.5"},
      {:mongodb, ">= 0.0.0"},
      {:poolboy, ">= 0.0.0"},
      {:timex, "~> 3.0"},
      {:bamboo, "~> 0.8"},
      {:bamboo_smtp, "~> 1.4.0"},

      # dev
      {:credo, "~> 0.9", only: [:dev, :test], runtime: false},
      {:edeliver, "~> 1.4.5"},
      {:distillery, "~> 1.5", runtime: false}
    ]
  end
end
