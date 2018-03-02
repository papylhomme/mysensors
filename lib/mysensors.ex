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
      MySensors.Bus,
      MySensors.TransportBus,
      MySensors.Network,
    ]

    children =
      case Application.get_env(:mysensors, :gateway, true) do
        false -> children
        true -> children ++ [MySensors.Gateway]
      end

    children =
      case Application.get_env(:mysensors, :serial, true) do
        false ->
          children

        true ->
          children ++
            [
              {Nerves.UART, [name: Nerves.UART]},
              MySensors.SerialBridge
            ]
      end

    opts = [strategy: :one_for_one, name: MySensors.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
