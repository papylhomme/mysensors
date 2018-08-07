defmodule MySensors.NetworksManager do
  alias MySensors.Network

  @moduledoc """
  A manager for networks
  """

  use GenServer, start: {__MODULE__, :start_link, []}
  require Logger


  # TODO save network errors and use them to enhance the results of `networks` call

  #########
  #  API
  #########

  @doc """
  Start the manager
  """
  @spec start_link() :: GenServer.on_start()
  def start_link() do
    GenServer.start_link(__MODULE__, {}, name: __MODULE__)
  end


  @doc """
  Get a list of registered networks with their state and configuration
  """
  @spec networks() :: %{optional(MySensors.uuid) => %{status: :running | :stopped, config: Network.config, info: Network.info}}
  def networks() do
    GenServer.call(__MODULE__, :networks)
  end


  @doc """
  Register a new network `name` using `config`
  """
  @spec register_network(Network.config) :: MySensors.uuid
  def register_network(config) do
    GenServer.call(__MODULE__, {:register_network, config})
  end


  @doc """
  Unregister a network
  """
  @spec unregister_network(MySensors.uuid) :: term()
  def unregister_network(uuid) do
    GenServer.call(__MODULE__, {:unregister_network, uuid})
  end


  @doc """
  Start a network
  """
  @spec start_network(MySensors.uuid) :: term()
  def start_network(uuid) do
    GenServer.call(__MODULE__, {:start_network, uuid})
  end


  @doc """
  Stop a network
  """
  @spec stop_network(MySensors.uuid) :: term()
  def stop_network(uuid) do
    GenServer.call(__MODULE__, {:stop_network, uuid})
  end


  ###################
  #  Implementation
  ###################

  # Initialize the server
  def init({}) do
    # Init supervisor and table, create state
    {:ok, supervisor} = DynamicSupervisor.start_link(strategy: :one_for_one)

    networks_db = Path.join(Application.get_env(:mysensors, :data_dir, "./"), "networks.db")
    {:ok, tid} = :dets.open_file(networks_db, ram_file: true, auto_save: 10)

    state = %{supervisor: supervisor, table: tid}

    # Look for networks in configuration file and register them
    Application.get_env(:mysensors, :networks, [])
    |> Enum.each(fn network -> _register_network(state, network) end)

    # Auto start networks
    _autostart_networks(state)

    {:ok, state}
  end


  # Handle call networks
  def handle_call(:networks, _from, state) do
    runnings =
      for {_, pid, _, _} <- DynamicSupervisor.which_children(state.supervisor), into: %{} do
        info = Network.info(pid)
        {info.uuid, info}
      end

    res = :dets.foldl(fn {uuid, config}, acc ->
      case Map.get(runnings, uuid) do
        nil -> put_in(acc, [uuid], %{status: :stopped, config: config})
        info -> put_in(acc, [uuid], %{status: :running, config: config, info: info})
      end
    end, %{}, state.table)

    {:reply, res, state}
  end


  # Handle call register_network
  def handle_call({:register_network, config}, _from, state) do
    {:reply, _register_network(state, config), state}
  end


  # Handle call unregister_network
  def handle_call({:unregister_network, uuid}, _from, state) do
    {:reply, _unregister_network(state, uuid), state}
  end


  # Handle call start_network
  def handle_call({:start_network, uuid}, _from, state) do
    case :dets.lookup(state.table, uuid) do
      [] -> {:reply, :not_found, state}
      [{uuid, network}] -> {:reply, _start_network(state, uuid, network), state}
    end
  end


  # Handle call stop_network
  def handle_call({:stop_network, uuid}, _from, state) do
    {:reply, _stop_network(state, uuid), state}
  end


  ############
  #  Private
  ############

  # Auto-starts configured networks
  def _autostart_networks(state) do
    :dets.traverse(state.table, fn {uuid, network} ->
      _start_network(state, uuid, network)
      :continue
    end)
  end


  # Register a new network
  def _register_network(state, network) do
    uuid = UUID.uuid5(:nil, "#{network.name}")

    case :dets.lookup(state.table, uuid) do
      [_] -> nil
      [] ->
        Logger.info "Registering network #{network.name} #{inspect network}"
        :ok = :dets.insert(state.table, {uuid, network})
        uuid
    end
  end


  # Register a network
  def _unregister_network(state, uuid) do
    :dets.delete(state.table, uuid)
  end


  # Start a network
  def _start_network(state, uuid, network) do
    Logger.info "Starting network #{network.name}"

    DynamicSupervisor.start_child(state.supervisor, %{
      id: String.to_atom(uuid),
      start: {Network, :start_link, [uuid, network]}
    })
  end


  # Stop a network
  defp _stop_network(state, uuid) do
    # TODO try to prevent call Network.info (cache the info maybe)
    child =
      state.supervisor
      |> DynamicSupervisor.which_children
      |> Enum.find(fn {_, pid, _, _} -> uuid == Network.info(pid).uuid end)

    case child do
      {_, pid, _, _} -> DynamicSupervisor.terminate_child(state.supervisor, pid)
      _ -> :not_found
    end
  end

end
