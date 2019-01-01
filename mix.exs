defmodule MySensors.Mixfile do
  use Mix.Project

  def project do
    [
      app: :mysensors,
      version: "0.1.0",
      elixir: "~> 1.7",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: {MySensors, []},
      extra_applications: [
        :logger,
        :tortoise # required by MQTTBridge
      ]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ex_doc, "~> 0.19", only: :dev, runtime: false},
      {:phoenix_pubsub, "~> 1.0"},
      {:elixir_uuid, "~> 1.2"},
      {:circuits_uart, "~> 1.3"}, # required by SerialBridge
      {:tortoise, "~> 0.9"} # required by MQTTBridge
    ]
  end
end
