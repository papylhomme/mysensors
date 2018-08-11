defmodule MySensors.Node do
  alias MySensors.Types
  alias MySensors.Bus
  alias MySensors.Sensor
  alias MySensors.MessageQueue
  alias __MODULE__.NodeUpdatedEvent

  @moduledoc """
  A server to interract with a MySensors node
  """

  defstruct uuid: nil,
            network: nil,
            node_id: nil,
            type: nil,
            version: nil,
            sketch_name: nil,
            sketch_version: nil,
            status: :unknown,
            battery: nil,
            last_seen: nil,
            sensors: %{}

  @typedoc "Sensors info"
  @type sensors :: %{optional(Types.id()) => pid}

  @typedoc "Node's info"
  @type t :: %__MODULE__{
          uuid: String.t(),
          network: String.t(),
          node_id: Types.id(),
          type: String.t(),
          version: String.t(),
          sketch_name: String.t(),
          sketch_version: String.t(),
          sensors: sensors
        }

  use GenServer
  require Logger

  #########
  #  API
  #########

  @doc """
  Start a node using the given uuid

  On startup the node is loaded from storage
  """
  @spec start_link({String.t(), any, String.t()}) :: GenServer.on_start()
  def start_link({network_uuid, table, uuid}) do
    GenServer.start_link(__MODULE__, {network_uuid, table, uuid}, name: MySensors.by_uuid(uuid))
  end

  @doc """
  Request information about the node
  """
  @spec info(pid) :: t
  def info(pid) do
    GenServer.call(pid, :info)
  end

  @doc """
  List the sensors
  """
  @spec sensors(pid) :: [Sensor.info()]
  def sensors(pid) do
    GenServer.call(pid, :list_sensors)
  end

  @doc """
  Get the node's message queue
  """
  @spec queue(pid) :: pid
  def queue(pid) do
    GenServer.call(pid, :queue)
  end

  @doc """
  Handle a specs updated event
  """
  @spec update_specs(pid, t) :: :ok
  def update_specs(pid, specs) do
    GenServer.cast(pid, {:update_specs, specs})
  end

  @doc """
  Send a command to the node
  """
  @spec command(pid, Types.id(), Types.command(), Types.type(), String.t()) :: :ok
  def command(pid, sensor_id, command, type, payload \\ "") do
    GenServer.cast(pid, {:node_command, sensor_id, command, type, payload})
  end

  ###############
  #  Internals
  ###############

  # Initialize the server
  def init({network_uuid, table, uuid}) do
    Bus.subscribe_node_messages(uuid)

    # init message queue
    {:ok, queue} = MessageQueue.start_link(network_uuid, fn event ->
      Bus.broadcast_node_commands(uuid, event)
    end)

    # init sensors
    [{_, node_specs}] = :dets.lookup(table, uuid)
    sensors =
      for {sensor_id, sensor_specs} <- node_specs.sensors, into: %{} do
        sensor_uuid = _sensor_uuid(uuid, sensor_id)
        {:ok, pid} = Sensor.start_link(sensor_uuid, uuid, sensor_specs)
        {sensor_uuid, {pid, sensor_specs}}
      end

    Logger.info("New node #{node_specs.node_id} online (#{inspect(node_specs.sensors)})")

    {:ok,
     %{
       message_queue: queue,
       node: %__MODULE__{
        uuid: uuid,
        network: network_uuid,
        node_id: node_specs.node_id,
        type: node_specs.type,
        version: node_specs.version,
        sketch_name: node_specs.sketch_name,
        sketch_version: node_specs.sketch_version,
        sensors: sensors
       }
     }}
  end

  # Handle info call
  def handle_call(:info, _from, state) do
    {:reply, state.node, state}
  end

  # Handle queue call
  def handle_call(:queue, _from, state) do
    {:reply, state.message_queue, state}
  end

  # Handle list_sensors call
  def handle_call(:list_sensors, _from, state) do
    res =
      state.node.sensors
      |> Enum.map(fn {_uuid, {pid, _spec}} -> Sensor.info(pid) end)

    {:reply, res, state}
  end

  # Handle node specs update
  # TODO more robust change detection
  def handle_cast({:update_specs, node_specs}, state = %{node: node}) do
    res =
      if Map.size(node.sensors) == Map.size(node_specs.sensors) do
        new_state =
          put_in(state, [:node], %{
            node
            | type: node_specs.type,
              version: node_specs.version,
              sketch_name: node_specs.sketch_name,
              sketch_version: node_specs.sketch_version
          })

        Logger.info("Node #{node.node_id} received a specs update")
        {:noreply, new_state}
      else
        Logger.warn("Node #{node.node_id} received incompatible specs update, restarting")
        {:stop, {:shutdown, :specs_updated}, state}
      end

    NodeUpdatedEvent.broadcast(node_specs)
    res
  end

  # Handle node commands
  def handle_cast({:node_command, sensor_id, command, type, payload}, state) do
    MessageQueue.push(state.message_queue, state.node.node_id, sensor_id, command, type, payload)
    {:noreply, state}
  end

  # Handle internal commands
  def handle_info(
        {:mysensors, :node_messages, msg = %{command: :internal, child_sensor_id: 255, type: type}},
        state = %{node: node}
      ) do
    new_node =
      case type do
        # handle battery level
        I_BATTERY_LEVEL ->
          Logger.debug("Node #{node.node_id} handling battery level: #{msg.payload}")
          node = %{node | battery: msg.payload}
          NodeUpdatedEvent.broadcast(node)
          node

        # handle pre sleep notification
        I_PRE_SLEEP_NOTIFICATION ->
          Logger.debug("Node #{node.node_id} handling pre sleep")
          node = %{node | status: "SLEEPING", last_seen: DateTime.utc_now()}
          NodeUpdatedEvent.broadcast(node)
          node

        # handle post sleep notification
        I_POST_SLEEP_NOTIFICATION ->
          Logger.debug("Node #{node.node_id} waking up")

          # flush queued message
          MessageQueue.flush(state.message_queue)

          # update status
          node = %{node | status: "RUNNING", last_seen: DateTime.utc_now()}
          NodeUpdatedEvent.broadcast(node)
          node

        # discard other commands
        _ ->
          node
      end

    {:noreply, %{state | node: new_node}}
  end

  # Handle incoming sensor messages
  def handle_info(
        {:mysensors, :node_messages, message = %{child_sensor_id: sensor_id}},
        state = %{node: node}
      ) do

    case Map.get(node.sensors, _sensor_uuid(node.uuid, sensor_id)) do
      {pid, _spec} -> Sensor.on_event(pid, message)
      _ -> Logger.warn("Node #{node.uuid} doesn't know sensor #{sensor_id} from message #{message}")
    end

    {:noreply, state}
  end

  # Handle unexpected messages
  def handle_info(msg, state) do
    Logger.warn("Node #{state.node.node_id} handling unexpected message #{inspect(msg)}")
    {:noreply, state}
  end

  # Generate an UUID for the given sensor
  defp _sensor_uuid(node_uuid, sensor_id) do
    UUID.uuid5(node_uuid, "#{sensor_id}")
  end



  defmodule NodeDiscoveredEvent do
    @moduledoc """
    An event generated when a new node is discovered
    """

    # Event struct
    defstruct uuid: nil, specs: nil

    @typedoc "The event struct"
    @type t :: %__MODULE__{uuid: MySensors.uuid(), specs: MySensors.Node.t()}

    @doc """
    Create and broadcast a NodeDiscoveredEvent
    """
    @spec broadcast(MySensors.Node.t()) :: t
    def broadcast(specs) do
      %__MODULE__{uuid: specs.uuid, specs: specs}
      |> Bus.broadcast_nodes_events()
    end
  end

  defmodule NodeUpdatedEvent do
    @moduledoc "An event generated when a node is updated"

    # Event struct
    defstruct uuid: nil, specs: nil

    @typedoc "The event struct"
    @type t :: %__MODULE__{uuid: MySensors.uuid(), specs: MySensors.Node.t()}

    @doc """
    Create and broadcast a NodeUpdatedEvent
    """
    @spec broadcast(MySensors.Node.t()) :: t
    def broadcast(specs) do
      %__MODULE__{uuid: specs.uuid, specs: specs}
      |> Bus.broadcast_nodes_events()
    end
  end
end
