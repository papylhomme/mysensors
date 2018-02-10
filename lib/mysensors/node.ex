defmodule MySensors.Node do
  alias MySensors.Types
  alias MySensors.Sensor
  alias __MODULE__.NodeUpdatedEvent

  @moduledoc """
  A server to interract with a MySensors node
  """

  defstruct node_id: nil,
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
  Helper generating an unique reference for the given node
  """
  @spec ref(Types.id()) :: atom
  def ref(node_id) do
    "#{__MODULE__}#{node_id}" |> String.to_atom()
  end

  @doc """
  Start a node using the given id

  On startup the node is loaded from storage
  """
  @spec start_link({any, Types.id()}) :: GenServer.on_start()
  def start_link({table, node_id}) do
    GenServer.start_link(__MODULE__, {table, node_id}, name: ref(node_id))
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
  Handle a specs updated event
  """
  @spec update_specs(pid, t) :: :ok
  def update_specs(pid, specs) do
    GenServer.cast(pid, {:update_specs, specs})
  end

  @doc """
  Send a message to the node

  For nodes reporting their running status (using [NodeManager](https://www.mysensors.org/download/node-manager)
  service messages), messages are queued and sent when the node awakes.
  """
  @spec send_message(pid, MySensors.Message.t()) :: :ok
  def send_message(pid, message) do
    GenServer.cast(pid, {:send_message, message})
  end

  ###############
  #  Internals
  ###############

  # Initialize the server
  def init({table, node_id}) do
    Phoenix.PubSub.subscribe(MySensors.PubSub, "node_#{node_id}")

    [{_id, node_specs}] = :dets.lookup(table, node_id)

    sensors =
      for {id, sensor_specs} <- node_specs.sensors, into: %{} do
        {:ok, pid} = Sensor.start_link(node_specs.node_id, sensor_specs)
        {id, pid}
      end

    Logger.info("New node #{node_specs.node_id} online (#{inspect(node_specs.sensors)})")

    {:ok,
     %{
       message_queue: [],
       node: %__MODULE__{
         node_id: node_specs.node_id,
         type: node_specs.type,
         version: node_specs.version,
         sketch_name: node_specs.sketch_name,
         sketch_version: node_specs.sketch_version,
         sensors: sensors
       }
     }}
  end

  # Handle info request
  def handle_call(:info, _from, state) do
    {:reply, state.node, state}
  end

  # Handle list_sensors
  def handle_call(:list_sensors, _from, state) do
    res =
      state.node.sensors
      |> Enum.map(fn {_id, pid} ->
        Sensor.info(pid)
      end)

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

  # Handle send message
  def handle_cast({:send_message, message}, state = %{node: node, message_queue: message_queue}) do
    case node do
      # when node is sleeping, queue the message
      %{status: "SLEEPING"} ->
        Logger.debug("Node #{node.node_id} queuing message #{message}")
        {:noreply, %{state | message_queue: message_queue ++ [message]}}

      _ ->
        message
        |> MySensors.Gateway.send_message()

        {:noreply, state}
    end
  end

  # Handle battery level
  def handle_info(
        {:mysensors_message,
         %{command: :internal, type: I_BATTERY_LEVEL, child_sensor_id: 255, payload: payload}},
        state = %{node: node}
      ) do
    Logger.debug("Node #{node.node_id} handling battery level: #{payload}")

    node = %{node | battery: payload}
    NodeUpdatedEvent.broadcast(node)

    {:noreply, %{state | node: node}}
  end

  # Handle heartbeat
  def handle_info(
        {:mysensors_message,
         %{command: :internal, type: I_HEARTBEAT_RESPONSE, child_sensor_id: 255}},
        state = %{node: node}
      ) do
    Logger.debug("Node #{node.node_id} handling heartbeat")

    node = %{node | last_seen: DateTime.utc_now()}
    NodeUpdatedEvent.broadcast(node)

    {:noreply, %{state | node: node}}
  end

  # Handle running status provided by NodeManager's service messages
  # When node awakes, flush the queued messages
  def handle_info(
        {:mysensors_message,
         %{command: :set, type: V_CUSTOM, child_sensor_id: 200, payload: payload}},
        state = %{node: node}
      ) do
    Logger.debug("Node #{node.node_id} handling status: #{payload}")

    # update status
    node = %{node | status: payload}
    NodeUpdatedEvent.broadcast(node)

    # flush queued message
    Enum.each(state.message_queue, fn message -> message |> MySensors.Gateway.send_message() end)

    {:noreply, %{state | node: node, message_queue: []}}
  end

  # Handle incoming messages
  def handle_info(
        {:mysensors_message, message = %{child_sensor_id: sensor_id}},
        state = %{node: node}
      ) do
    if Map.has_key?(node.sensors, sensor_id) do
      Sensor.on_event(node.sensors[sensor_id], message)
    else
      Logger.warn("Node #{node.node_id} handling unexpected event #{message}")
    end

    {:noreply, state}
  end

  # Handle unexpected messages
  def handle_info(msg, state) do
    Logger.warn("Node #{state.node.node_id} handling unexpected message #{inspect(msg)}")
    {:noreply, state}
  end

  defmodule NodeDiscoveredEvent do
    @moduledoc """
    An event generated when a new node is discovered
    """

    # Event struct
    defstruct node_id: nil, specs: nil

    @typedoc "The event struct"
    @type t :: %__MODULE__{node_id: Types.id(), specs: MySensors.Node.t()}

    @doc """
    Create a NodeDiscoveredEvent
    """
    @spec new(MySensors.Node.t()) :: t
    def new(specs) do
      %__MODULE__{node_id: specs.node_id, specs: specs}
    end

    def broadcast(specs) do
      event = new(specs)
      Phoenix.PubSub.broadcast(MySensors.PubSub, "nodes_events", {:mysensors, :node_event, event})
    end
  end

  defmodule NodeUpdatedEvent do
    @moduledoc """
    An event generated when a node is updated
    """

    # Event struct
    defstruct node_id: nil, specs: nil

    @typedoc "The event struct"
    @type t :: %__MODULE__{node_id: Types.id(), specs: MySensors.Node.t()}

    @doc """
    Create a NodeUpdatedEvent
    """
    @spec new(MySensors.Node.t()) :: t
    def new(specs) do
      %__MODULE__{node_id: specs.node_id, specs: specs}
    end

    def broadcast(specs) do
      event = new(specs)
      Phoenix.PubSub.broadcast(MySensors.PubSub, "nodes_events", {:mysensors, :node_event, event})
    end
  end
end
