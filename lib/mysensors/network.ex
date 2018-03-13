defmodule MySensors.Network do
  alias MySensors.Node
  alias MySensors.MessageQueue
  alias __MODULE__.PresentationAccumulator

  @moduledoc """
  A server to interract with a MySensors network
  """

  @supervisor __MODULE__.Supervisor

  use GenServer, start: {__MODULE__, :start_link, []}
  require Logger


  #########
  #  API
  #########

  @doc """
  Start the server
  """
  @spec start_link() :: GenServer.on_start()
  def start_link() do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @doc """
  List the known nodes
  """
  @spec nodes() :: [Node.t()]
  def nodes do
    GenServer.call(__MODULE__, :list_nodes)
  end

  @doc """
  Send a discover command and request presentation from discovered nodes
  """
  @spec scan() :: :ok
  def scan do
    GenServer.cast(__MODULE__, :scan)
  end

  @doc """
  Request presentation from a node
  """
  @spec request_presentation(Types.id()) :: :ok
  def request_presentation(node) do
    :ok = GenServer.cast(__MODULE__, {:request_presentation, node})
  end

  ####################
  #  Implementation
  ####################

  # Initialize the server
  def init(:ok) do
    nodes_db = Path.join(Application.get_env(:mysensors, :data_dir, "./"), "nodes.db")
    {:ok, tid} = :dets.open_file(nodes_db, ram_file: true, auto_save: 10)

    {:ok, queue} = MessageQueue.start_link()
    {:ok, _} = Supervisor.start_link([], strategy: :one_for_one, name: @supervisor)

    Logger.info("Initializing nodes from storage...")

    :dets.traverse(tid, fn {id, _node_specs} ->
      _start_child(tid, id)
      :continue
    end)

    MySensors.TransportBus.subscribe_incoming()

    {:ok, %{table: tid, presentations: %{}, queue: queue}}
  end

  # Handle list_nodes call
  # TODO use db to list nodes, and report crashed ones (when its server is no longer running)
  def handle_call(:list_nodes, _from, state) do
    res =
      Supervisor.which_children(@supervisor)
      |> Enum.map(fn {_id, pid, _, _} ->
        Map.put(Node.info(pid), :pid, pid)
      end)

    {:reply, res, state}
  end

  # Handle scan cast
  def handle_cast(:scan, state) do
    Logger.info("Sending discover request")
    MySensors.Gateway.send_message(255, 255, :internal, I_DISCOVER_REQUEST)

    # manually request presentation from gateway
    request_presentation(0)

    {:noreply, state}
  end

  # Handle request presentation cast
  def handle_cast({:request_presentation, node_id}, state) do
    {:noreply, %{state | presentations: _request_presentation(state, node_id)}}
  end

  # Handle presentation initiated by node
  def handle_info(
        {:mysensors_incoming,
         msg = %{command: :presentation, child_sensor_id: 255, node_id: node_id}},
        state
      ) do
    acc = get_in(state, [:presentations, node_id])

    presentations =
      case acc do
        nil ->
          Logger.info("Receiving presentation from node #{node_id}...")
          p = _init_accumulator(state.presentations, node_id)
          send(p[node_id], msg)
          p

        pid ->
          send(pid, msg)
          state.presentations
      end

    {:noreply, %{state | presentations: presentations}}
  end

  # Forward presentation messages to accumulator
  def handle_info({:mysensors_incoming, msg = %{command: :presentation, node_id: node_id}}, state) do
    acc = get_in(state, [:presentations, node_id])
    unless is_nil(acc), do: send(acc, msg)
    {:noreply, state}
  end

  # Forward sketch info messages to accumulator
  def handle_info(
        {:mysensors_incoming,
         msg = %{node_id: node_id, child_sensor_id: 255, command: :internal, type: t}},
        state
      )
      when t in [I_SKETCH_NAME, I_SKETCH_VERSION] do
    acc = get_in(state, [:presentations, node_id])
    unless is_nil(acc), do: send(acc, msg)
    {:noreply, state}
  end

  # Handle internal commands
  def handle_info(
        {:mysensors_incoming,
         msg = %{
           command: :internal,
           child_sensor_id: 255,
           node_id: node_id
         }},
        state
      ) do

    # Handle node awakening to flush related presentation requests
    if msg.type == I_POST_SLEEP_NOTIFICATION do
      MessageQueue.flush(state.queue, fn msg -> msg.node_id == node_id end)
    end

    # Request presentation if node is unknown
    case _node_known?(state, node_id) do
      true -> {:noreply, state}
      false -> {:noreply, %{state | presentations: _request_presentation(state, node_id)}}
    end
  end

  # Discard remaining MySensors messages
  def handle_info({:mysensors_incoming, _msg}, state) do
    {:noreply, state}
  end

  # Handle accumulator finishing
  def handle_info({:DOWN, _, _, _, {:shutdown, acc}}, state) do
    case _accumulator_ready?(acc) do
      false ->
        Logger.debug("Discarding empty accumulator for node #{acc.node_id} #{inspect(acc)}")

      true ->
        Logger.debug("Presentation accumulator for node #{acc.node_id} finishing #{inspect(acc)}")
        _node_presentation(state, acc)
    end

    {_, new_state} = pop_in(state, [:presentations, acc.node_id])
    {:noreply, new_state}
  end

  ##############
  #  Internals
  ##############

  # Start a supervised node server
  defp _start_child(state, node_id) do
    child_spec = Supervisor.child_spec({Node, {state.table, node_id}}, id: node_id)
    {:ok, _pid} = Supervisor.start_child(@supervisor, child_spec)
  end

  # Initialize a presentation accumulator for the given node
  defp _init_accumulator(presentations, node, type \\ nil, version \\ nil) do
    {:ok, pid} = PresentationAccumulator.start_link(node, type, version)
    Process.monitor(pid)
    put_in(presentations, [node], pid)
  end

  # Test if an accumulator has received sufficient information
  defp _accumulator_ready?(acc) do
    not (is_nil(acc.node_id) or is_nil(acc.type) or map_size(acc.sensors) == 0)
  end

  # Test whether is known in the system or not
  defp _node_known?(state, node_id) do
    :dets.lookup(state.table, node_id) != []
  end

  # Request presentation for the given node
  defp _request_presentation(state, node_id) do
    case Map.has_key?(state.presentations, node_id) do
      true -> state.presentations
      false ->
        Logger.info("Requesting presentation from node #{node_id}...")
        MessageQueue.push(state.queue, node_id, 255, :internal, I_PRESENTATION)
        state.presentations |> _init_accumulator(node_id)
      end
  end

  # Handle presentation from a node
  defp _node_presentation(state, acc = %{node_id: node_id}) do
    case _node_known?(state, node_id) do
      false ->
        Logger.info("New node registration #{inspect(acc)}")
        :ok = :dets.insert(state.table, {node_id, acc})
        _start_child(state, node_id)

        Node.NodeDiscoveredEvent.broadcast(acc)

      true ->
        :ok = :dets.insert(state.table, {node_id, acc})
        node = Node.ref(node_id)
        unless is_nil(Process.whereis(node)), do: Node.update_specs(node, acc)
    end
  end

  # An accumulator for presentation events
  defmodule PresentationAccumulator do
    @moduledoc false
    use GenServer

    @timeout 1000

    @doc """
    Start the accumulator
    """
    @spec start_link(Types.id(), String.t(), String.t()) :: GenServer.on_start()
    def start_link(node_id, type \\ nil, version \\ nil) do
      GenServer.start(__MODULE__, {node_id, type, version})
    end

    # Initialize the accumulator
    def init({node_id, type, version}) do
      specs = %Node{
        node_id: node_id,
        type: type,
        version: version,
        sketch_name: nil,
        sketch_version: nil,
        sensors: %{}
      }

      {:ok, specs, @timeout}
    end

    # Handle presentation events
    def handle_info(msg = %{command: :internal}, state) do
      new_state =
        case msg.type do
          I_SKETCH_NAME -> %{state | sketch_name: msg.payload}
          I_SKETCH_VERSION -> %{state | sketch_version: msg.payload}
          _ -> state
        end

      {:noreply, new_state, @timeout}
    end

    # Handle presentation events
    def handle_info(msg = %{command: :presentation}, state) do
      new_state =
        case msg.child_sensor_id do
          255 ->
            %{state | type: msg.type, version: msg.payload}

          # Skip the NodeManager CUSTOM sensor (status is handled internally by `MySensors.Node`)
          200 ->
            state

          sensor_id ->
            %{
              state
              | sensors: Map.put(state.sensors, sensor_id, {sensor_id, msg.type, msg.payload})
            }
        end

      {:noreply, new_state, @timeout}
    end

    # Handle timeout to shutdown the accumulator
    def handle_info(:timeout, state) do
      {:stop, {:shutdown, state}, state}
    end
  end
end
