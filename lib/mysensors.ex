defmodule MySensors do
  @moduledoc """
  MySensors Application
  """

  use Application

  # Name of the registry mapping UUIDs to processes
  @registry_name MySensors.Registry


  @doc """
  Setup a GenServer `:via` tuple using the given uuid
  """
  @spec by_uuid(String.t()) :: GenServer.server()
  def by_uuid(uuid) do
    {:via, Registry, {@registry_name, uuid}}
  end


  @doc """
  Start the application
  """
  def start(_type, _args) do
    children = [
      {Registry, keys: :unique, name: @registry_name},
      MySensors.Bus,
      MySensors.TransportBus,
      %{id: :remote, start: {MySensors.Network, :start_link, [%{uuid: UUID.uuid5(:nil, "remote_network"), transport: {:remote, ""}}]}},
      {MySensors.Network, %{uuid: UUID.uuid5(:nil, "mqtt_bridge"), transport: {MySensors.MQTTBridge, %{}}}}
    ]

    opts = [strategy: :one_for_one, name: MySensors.Supervisor]
    Supervisor.start_link(children, opts)
  end

end
