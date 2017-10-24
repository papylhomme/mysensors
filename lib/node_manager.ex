defmodule MySensors.NodeManager do

  alias MySensors.Node


  @moduledoc """
  Module responsible to track nodes on the network
  """

  use GenServer, start: {__MODULE__, :start_link, []}

  require Logger

  @db "#{__MODULE__}.db"


  @doc """
  Start the manager
  """
  @spec start_link() :: GenServer.on_start
  def start_link() do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end


  @doc """
  Process a node presentation
  """
  @spec on_node_presentation(MySensors.Message.presentation) :: :ok
  def on_node_presentation(node_spec) do
    GenServer.cast(__MODULE__, {:node_presentation, node_spec})
  end


  @doc """
  Process a node event
  """
  @spec on_node_event(MySensors.Message.t) :: :ok
  def on_node_event(msg) do
    GenServer.cast(__MODULE__, {:node_event, msg})
  end


  @doc """
  List the known nodes
  """
  @spec nodes() :: [MySensors.Node.t]
  def nodes do
    GenServer.call(__MODULE__, :list_nodes)
  end


  # Initialize the manager
  def init(:ok) do
    {:ok, tid} = :dets.open_file(@db, [ram_file: true, auto_save: 10])
    {:ok, supervisor} = Supervisor.start_link([], strategy: :one_for_one, name: __MODULE__.Supervisor)

    state = %{table: tid, supervisor: supervisor}

    Logger.info "Initializing nodes from storage..."
    :dets.traverse(tid, fn {id, _node_specs} ->
      _start_child(state, id)
      :continue
    end)

    {:ok, state}
  end


  # Handle list_nodes
  def handle_call(:list_nodes, _from, state) do
    res =
      Supervisor.which_children(state.supervisor)
      |> Enum.map(fn {_id, pid, _, _} ->
        Map.put(Node.info(pid), :pid, pid)
      end)

    {:reply, res, state}
  end


  # Handle node presentation
  def handle_cast({:node_presentation, node_specs = %{node_id: node_id}}, state = %{table: tid}) do
    case :dets.lookup(tid, node_id) do
      [] ->
        Logger.info "New node registration #{inspect node_specs}"

        :ok = :dets.insert(tid, {node_id, node_specs})
        _start_child(state, node_id)

        Node.NodeDiscoveredEvent.new(node_specs)
        |> MySensors.NodeEvents.on_node_event

      _ ->
        :ok = :dets.insert(tid, {node_id, node_specs})

        case _node_pid(state, node_id) do
          nil -> []
          pid ->
            Node.on_specs_updated(pid, node_specs)
        end
    end

    {:noreply, state}
  end


  # Handle node event
  #
  # If an event comes for an unknown node, the event is discarded and
  # a request for presentation is sent to the node.
  def handle_cast({:node_event, msg = %{node_id: node_id}}, state) do
    case :dets.lookup(state.table, node_id) do
      []  -> :ok = MySensors.PresentationManager.request_presentation(node_id)
      _   ->
        case _node_pid(state, node_id) do
          nil   -> Logger.warn "Received event for unknow node #{node_id}: #{msg}"
          node  -> Node.on_event(node, msg)
        end
    end

    {:noreply, state}
  end


  # Start a supervised node
  defp _start_child(state, node_id) do
    {:ok, _pid} = Supervisor.start_child(state.supervisor, Supervisor.child_spec({Node, {state.table, node_id}}, id: node_id))
  end


  # Get the pid of the server managing the given node
  def _node_pid(state, node_id) do
    Supervisor.which_children(state.supervisor)
    |> Enum.find_value(fn {id, pid, _, _} -> if id == node_id, do: pid, else: nil end)
  end

end
