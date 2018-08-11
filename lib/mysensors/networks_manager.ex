defmodule MySensors.NetworksManager do
  alias MySensors.Network
  alias MySensors.Events

  @moduledoc """
  A manager for networks
  """

  use GenServer, start: {__MODULE__, :start_link, []}
  require Logger


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
  @spec networks() :: %{optional(MySensors.uuid) => %{status: Network.status, config: Network.config}}
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
    # Trap exits for networks processes
    Process.flag(:trap_exit, true)

    # Init table, create state
    networks_db = Path.join(Application.get_env(:mysensors, :data_dir, "./"), "networks.db")
    {:ok, tid} = :dets.open_file(networks_db, ram_file: true, auto_save: 10)

    state = %{processes: %{}, table: tid}

    # Look for networks in configuration file and register them
    Application.get_env(:mysensors, :networks, [])
    |> Enum.each(fn network -> _register_network(state, network) end)

    # Auto start networks
    {:ok, _autostart_networks(state)}
  end


  # Handle call networks
  def handle_call(:networks, _from, state) do
    res = :dets.foldl(fn {uuid, config}, acc ->
      case Map.get(state.processes, uuid) do
        nil -> put_in(acc, [uuid], %{status: :stopped, config: config})
        {:running, pid} -> put_in(acc, [uuid], %{status: {:running, Network.info(pid)}, config: config})
        {:error, error} -> put_in(acc, [uuid], %{status: {:error, error}, config: config})
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
      [] -> {:reply, :not_registered, state}
      [{uuid, network}] ->
        {res, processes} =  _start_network(state, uuid, network)
        {:reply, res, %{state | processes: processes}}
    end
  end


  # Handle call stop_network
  def handle_call({:stop_network, uuid}, _from, state) do
    {:reply, _stop_network(state, uuid), state}
  end


  # Handle network process shutdown
  def handle_info({:EXIT, from, reason}, state) do
    case Enum.find(state.processes, fn {_uuid, {status, pid}} -> status == :running and pid == from end) do
      {uuid, _} ->
        Logger.info("Network #{uuid} stopped: #{inspect reason}")
        Events.NetworkStatusChanged.broadcast(uuid, :stopped)
        {:noreply, %{state | processes: Map.delete(state.processes, uuid)}}

      _ ->
        {:noreply, state}
    end

  end


  ############
  #  Private
  ############

  # Auto-starts configured networks
  def _autostart_networks(state) do
    :dets.foldl(fn {uuid, config}, acc ->
      {_res, processes} = _start_network(acc, uuid, config)
      %{acc | processes: processes}
    end, state, state.table)
  end


  # Register a new network
  def _register_network(state, network) do
    uuid = UUID.uuid5(:nil, "#{network.name}")

    case :dets.lookup(state.table, uuid) do
      [_] -> nil
      [] ->
        :ok = :dets.insert(state.table, {uuid, network})
        Logger.info "New network #{network.name} registered"
        Events.NetworkRegistered.broadcast(uuid, network)
        uuid
    end
  end


  # Unregister a network
  def _unregister_network(state, uuid) do
    case :dets.lookup(state.table, uuid) do
      [] -> :not_registered
      [_] ->
        :dets.delete(state.table, uuid)
        Events.NetworkUnregistered.broadcast(uuid)
    end
  end


  # Start a network
  def _start_network(state, uuid, network) do
    Logger.info "Starting network #{network.name}"

    res = Network.start_link(uuid, network)

    processes =
      case res do
        {:ok, pid} ->
          Events.NetworkStatusChanged.broadcast(uuid, {:running, Network.info(pid)})
          Map.put(state.processes, uuid, {:running, pid})

        {:error, {:already_started, _pid}} ->
          state.processes # nothing to do

        _ ->
          Logger.warn("Error starting network #{network.name}: #{inspect res}")
          Events.NetworkStatusChanged.broadcast(uuid, {:error, res})
          Map.put(state.processes, uuid, {:error, inspect res})
      end

    {res, processes}
  end


  # Stop a network
  defp _stop_network(state, uuid) do
    case Map.get(state.processes, uuid) do
      {:running, pid} -> Process.exit(pid, :kill)
      _ -> :not_running
    end
  end

end
