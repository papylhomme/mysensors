defmodule MySensors do
  @moduledoc """
  MySensors Application
  """

  use Application
  require Logger

  alias MySensors.NetworksManager
  alias MySensors.Network
  alias MySensors.Node

  # Name of the registry mapping UUIDs to processes
  @registry_name MySensors.Registry


  @typedoc "UUIDv5 identifier"
  @type uuid :: String.t


  @doc """
  Setup a GenServer `:via` tuple using the given uuid
  """
  @spec by_uuid(uuid) :: GenServer.server()
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
      MySensors.NetworksManager
    ]

    # Init main supervisor
    Supervisor.start_link(children, [strategy: :one_for_one, name: MySensors.Supervisor])
  end


  @doc """
  List the running networks
  """
  @spec networks() :: []
  def networks do
    NetworksManager.networks
  end


  @doc """
  List the known nodes
  """
  def nodes do
    for {uuid, network} <- networks(), match?({:running, _info}, network.status),
      node <- Network.nodes(by_uuid(uuid)), into: %{} do
        {node.uuid, node}
    end
  end


  @doc """
  List the known sensors
  """
  def sensors do
    for {uuid, network} <- networks(), match?({:running, _info}, network.status),
      node <- Network.nodes(by_uuid(uuid)),
        sensor <- Node.sensors(by_uuid(node.uuid)), into: %{} do
          {sensor.uuid, sensor}
    end
  end


  @doc """
  Start a new network
  """
  def start_network(uuid) do
    NetworksManager.start_network(uuid)
  end


  @doc """
  Stop a network
  """
  def stop_network(uuid) do
    NetworksManager.stop_network(uuid)
  end

end
