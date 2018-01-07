defmodule MySensors do

  @moduledoc """
  MySensors Application
  """

  use Application


  @doc """
  Start the application
  """
  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    children = [
      supervisor(Phoenix.PubSub.PG2, [MySensors.PubSub, []]),
      MySensors.NodeManager,
      MySensors.PresentationManager,
      MySensors.DiscoveryManager,
      MySensors.Gateway,
      {Nerves.UART, [name: Nerves.UART]},
      MySensors.SerialBridge,
    ]

    opts = [strategy: :one_for_one, name: MySensors.Supervisor]
    Supervisor.start_link(children, opts)
  end

end

