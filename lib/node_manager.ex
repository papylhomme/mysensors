defmodule MySensors.NodeManager do

  @moduledoc """
  Module responsible to track nodes on the network
  """

  use GenServer

  require Logger

  @db "#{__MODULE__}.db"


  @doc """
  Start the manager
  """
  def start_link(_) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end


  @doc """
  Process a node presentation
  """
  def on_node_presentation(node_spec) do
    GenServer.cast(__MODULE__, {:node_presentation, node_spec})
  end


  @doc """
  Process a node event
  """
  def on_node_event(msg) do
    GenServer.cast(__MODULE__, {:node_event, msg})
  end


  @doc """
  List the known nodes
  """
  def nodes do
    GenServer.call(__MODULE__, :list_nodes)
  end


  # Initialize the manager
  def init(_) do
    {:ok, tid} = :dets.open_file(@db, [ram_file: true, auto_save: 10])
    {:ok, supervisor} = Supervisor.start_link([], strategy: :one_for_one, name: __MODULE__.Supervisor)

    Logger.info "Initializing nodes from storage..."
    :dets.traverse(tid, fn {id, node_specs} ->
      Supervisor.start_child(supervisor, Supervisor.child_spec({MySensors.Node, node_specs}, id: id))
      :continue
    end)

    {:ok, %{table: tid, supervisor: supervisor}}
  end


  # Handle list_nodes
  def handle_call(:list_nodes, _from, state) do
    res =
      Supervisor.which_children(state.supervisor)
      |> Enum.map(fn {_id, pid, _, _} ->
        put_in(MySensors.Node.info(pid), [:pid], pid)
      end)

    {:reply, res, state}
  end


  # Handle node presentation
  def handle_cast({:node_presentation, node_specs = %{node_id: node_id}}, state = %{table: tid}) do
    case :dets.lookup(tid, node_id) do
      [] ->
        Logger.info "New node registration #{inspect node_specs}"

        :dets.insert(tid, {node_id, node_specs})
        Supervisor.start_child(state.supervisor, Supervisor.child_spec({MySensors.Node, node_specs}, id: node_id))
        MySensors.NodeEvents.notify({:new_node, node_specs})

      _ ->
        Logger.warn "Updating node spec #{inspect node_specs}"

        #TODO handle node changed (restart ?)

        :dets.insert(tid, {node_id, node_specs})
        MySensors.NodeEvents.notify({:updated_node, node_specs})
    end

    {:noreply, state}
  end


  # Handle node event
  def handle_cast({:node_event, msg = %{node_id: node_id}}, state) do
    case :dets.lookup(state.table, node_id) do
      []  -> :ok = MySensors.PresentationManager.request_presentation(node_id)
      _   ->
        node =
          Supervisor.which_children(state.supervisor)
          |> Enum.find_value(fn {id, pid, _, _} -> if id == node_id, do: pid, else: nil end)

        case node do
          nil   -> Logger.warn "Received event for unknow node #{node_id}: #{msg}"
          node  -> MySensors.Node.on_event(node, msg)
        end
    end

    {:noreply, state}
  end


end
