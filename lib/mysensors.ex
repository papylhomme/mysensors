defmodule MySensors do
  @moduledoc """
  MySensors Application
  """

  use Application
  require Logger

  # Name of the registry mapping UUIDs to processes
  @registry_name MySensors.Registry


  # Name of the network supervisor
  @supervisor_networks MySensors.NetworksSupervisor


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
      {DynamicSupervisor, strategy: :one_for_one, name: @supervisor_networks}
    ]

    # Init main supervisor
    opts = [strategy: :one_for_one, name: MySensors.Supervisor]
    {:ok, sup} = Supervisor.start_link(children, opts)

    # Init networks
    _init_networks()

    {:ok, sup}
  end


  @doc """
  List the running networks
  """
  @spec networks() :: []
  def networks do
    @supervisor_networks
    |> DynamicSupervisor.which_children
    |> Enum.map(fn {_, pid, _, _} -> MySensors.Network.info(pid) end)
  end


  @doc """
  Start a new network
  """
  def start_network(id, transport) do
    Logger.info "Starting network #{id}"

    {:ok, _pid} = 
      @supervisor_networks
      |> DynamicSupervisor.start_child(%{
        id: id,
        start: {MySensors.Network, :start_link, [%{id: id, uuid: UUID.uuid5(:nil, "#{id}"), transport: transport}]}
      })
  end


  @doc """
  Stop a network
  """
  def stop_network(uuid) do
    child =
      @supervisor_networks
      |> DynamicSupervisor.which_children
      |> Enum.find(fn {_, pid, _, _} -> uuid == MySensors.Network.info(pid).uuid end)

    case child do
      {_, pid, _, _} -> DynamicSupervisor.terminate_child(@supervisor_networks, pid)
      _ -> nil
    end
  end


  # Read config and start networks accordingly
  defp _init_networks do
    Application.get_env(:mysensors, :networks, %{})
    |> Enum.each(fn {id, config} -> start_network(id, config) end)
  end

end
