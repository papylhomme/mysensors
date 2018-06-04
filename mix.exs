defmodule MySensors.Mixfile do
  use Mix.Project

  def project do
    [
      app: :mysensors,
      version: "0.1.0",
      elixir: "~> 1.5",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: {MySensors, []},
      extra_applications: [:logger, :tortoise]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ex_doc, "~> 0.16", only: :dev, runtime: false},
      {:nerves_uart, "~> 1.2"}, # required by SerialBridge
      {:phoenix_pubsub, "~> 1.0"},
      {:tortoise, "~> 0.1.0"}
    ]
  end
end
