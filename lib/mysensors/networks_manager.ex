defmodule MySensors.NetworksManager do
  @moduledoc """
  A manager for networks
  """

  use GenServer, start: {__MODULE__, :start_link, []}
  require Logger


  # TODO save network errors and use them to enhance the results of `networks` call

  #########
  #  API
  #########

  def start_link() do
    GenServer.start_link(__MODULE__, {}, name: __MODULE__)
  end


  def networks() do
    GenServer.call(__MODULE__, :networks)
  end


  def register_network(id, config) do
    GenServer.call(__MODULE__, {:register_network, id, config})
  end


  def unregister_network(uuid) do
    GenServer.call(__MODULE__, {:unregister_network, uuid})
  end


  def start_network(uuid) do
    GenServer.call(__MODULE__, {:start_network, uuid})
  end


  def stop_network(uuid) do
    GenServer.call(__MODULE__, {:stop_network, uuid})
  end


  ###################
  #  Implementation
  ###################

  def init({}) do
    # Init supervisor and table, create state
    {:ok, supervisor} = DynamicSupervisor.start_link(strategy: :one_for_one)

    networks_db = Path.join(Application.get_env(:mysensors, :data_dir, "./"), "networks.db")
    {:ok, tid} = :dets.open_file(networks_db, ram_file: true, auto_save: 10)

    state = %{supervisor: supervisor, table: tid}

    # Look for networks in configuration file and register them
    Application.get_env(:mysensors, :networks, %{})
    |> Enum.each(fn {name, config} ->
      _register_network(state, %{name: name, config: config})
    end)

    # Auto start networks
    _start_networks(state) 

    {:ok, state}
  end


  def handle_call(:networks, _from, state) do
    runnings =
      for {_, pid, _, _} <- DynamicSupervisor.which_children(state.supervisor), into: %{} do
        info = MySensors.Network.info(pid)
        {info.uuid, info}
      end

    res = :dets.foldl(fn {uuid, _network}, acc ->
      case Map.get(runnings, uuid) do
        nil -> Map.put(acc, uuid, :stopped)
        info -> Map.put(acc, uuid, {:running, info})
      end
    end, %{}, state.table)

    {:reply, res, state}
  end


  def handle_call({:register_network, name, config}, _from, state) do
    {:reply, _register_network(state, %{name: name, config: config}), state}
  end


  def handle_call({:unregister_network, uuid}, _from, state) do
    {:reply, :dets.delete(state.table, uuid), state}
  end



  def handle_call({:start_network, uuid}, _from, state) do
    case :dets.lookup(state.table, uuid) do
      [] -> {:reply, :not_found, state}
      [{uuid, network}] -> {:reply, _start_network(state, uuid, network), state}
    end
  end


  def handle_call({:stop_network, uuid}, _from, state) do
    {:reply, _stop_network(state, uuid), state}
  end


  ############
  #  Private
  ############

  def _register_network(state, network) do
    uuid = UUID.uuid5(:nil, "#{network.name}")

    case :dets.lookup(state.table, uuid) do
      [_] -> nil
      [] -> 
        Logger.info "Registering network #{network.name}"
        :ok = :dets.insert(state.table, {uuid, network})
        uuid
    end
  end


  def _start_networks(state) do
    :dets.traverse(state.table, fn {uuid, network} ->
      _start_network(state, uuid, network)
      :continue
    end)
  end


  def _start_network(state, uuid, network) do
    Logger.info "Starting network #{network.name}"

    DynamicSupervisor.start_child(state.supervisor, %{
      id: String.to_atom(uuid),
      start: {MySensors.Network, :start_link, [%{name: network.name, uuid: uuid, transport: network.config}]}
    })
  end


  defp _stop_network(state, uuid) do
    child =
      state.supervisor
      |> DynamicSupervisor.which_children
      |> Enum.find(fn {_, pid, _, _} -> uuid == MySensors.Network.info(pid).uuid end)

    case child do
      {_, pid, _, _} -> DynamicSupervisor.terminate_child(state.supervisor, pid)
      _ -> :not_found
    end
  end

end
