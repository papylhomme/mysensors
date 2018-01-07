defmodule MySensors.Node do

  alias MySensors.Types
  alias MySensors.Sensor
  alias __MODULE__.NodeUpdatedEvent

  @moduledoc """
  A server to interract with a MySensors node

  TODO support offline/online/lastseen/heartbeat and such

  TODO use a supervisor for child sensors ?
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
  @type sensors :: %{optional(Types.id) => pid}

  @typedoc "Node's info"
  @type t :: %__MODULE__{node_id: Types.id, type: String.t, version: String.t, sketch_name: String.t, sketch_version: String.t, sensors: sensors}


  use GenServer
  require Logger


  @doc """
  Helper generating an unique reference for the given node
  """
  @spec ref(Types.id) :: atom
  def ref(node_id) do
    "#{__MODULE__}#{node_id}" |> String.to_atom
  end



  @doc """
  Start a node using the given id

  On startup the node is loaded from storage
  """
  @spec start_link({any, Types.id}) :: GenServer.on_start
  def start_link({table, node_id}) do
    GenServer.start_link(__MODULE__, {table, node_id}, [name: ref(node_id)])
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
  @spec sensors(pid) :: [Sensor.info]
  def sensors(pid) do
    GenServer.call(pid, :list_sensors)
  end


  @doc """
  Handle a specs updated event
  """
  @spec on_specs_updated(pid, t) :: :ok
  def on_specs_updated(pid, specs) do
    GenServer.cast(pid, {:specs_updated, specs})
  end


  # Initialize the server
  def init({table, node_id}) do
    Phoenix.PubSub.subscribe MySensors.PubSub, "node_#{node_id}"

    [{_id, node_specs}] = :dets.lookup(table, node_id)

    sensors =
      for {id, sensor_specs} <- node_specs.sensors, into: %{} do
        {:ok, pid} = Sensor.start_link(node_specs.node_id, sensor_specs)
        {id, pid}
      end

    Logger.info "New node #{node_specs.node_id} online (#{inspect node_specs.sensors})"

    {:ok, %__MODULE__{
      node_id: node_specs.node_id,
      type: node_specs.type,
      version: node_specs.version,
      sketch_name: node_specs.sketch_name,
      sketch_version: node_specs.sketch_version,
      sensors: sensors}
    }
  end


  # Handle info request
  def handle_call(:info, _from, state) do
    {:reply, state, state}
  end


  # Handle list_sensors
  def handle_call(:list_sensors, _from, state) do
    res =
      state.sensors
      |> Enum.map(fn {_id, pid} ->
        Sensor.info(pid)
      end)

    {:reply, res, state}
  end


  # Handle node specs updated
  # TODO more robust change detection
  def handle_cast({:specs_updated, node_specs}, state) do
    res =
      if Map.size(state.sensors) == Map.size(node_specs.sensors) do
        new_state = %{state |
          type: node_specs.type,
          version: node_specs.version,
          sketch_name: node_specs.sketch_name,
          sketch_version: node_specs.sketch_version,
        }

        Logger.info "Node #{state.node_id} received a specs update"
        {:noreply, new_state}
      else
        Logger.warn "Node #{state.node_id} received incompatible specs update, restarting"
        {:stop, {:shutdown, :specs_updated}, state}
      end

    NodeUpdatedEvent.broadcast(node_specs)
    res
  end


  # Handle battery level
  def handle_info({:mysensors_message, %{command: :internal, type: I_BATTERY_LEVEL, child_sensor_id: 255, payload: payload}}, state) do
    Logger.debug "Node #{state.node_id} handling battery level: #{payload}"

    new_state = %{state | battery: payload}
    NodeUpdatedEvent.broadcast(new_state)

    {:noreply, new_state}
  end


  # Handle heartbeat
  def handle_info({:mysensors_message, %{command: :internal, type: I_HEARTBEAT_RESPONSE, child_sensor_id: 255}}, state) do
    Logger.debug "Node #{state.node_id} handling heartbeat"

    new_state = %{state | last_seen: DateTime.utc_now}
    NodeUpdatedEvent.broadcast(new_state)

    {:noreply, new_state}
  end


  # Handle running status
  def handle_info({:mysensors_message, %{command: :set, type: V_CUSTOM, child_sensor_id: 200, payload: payload}}, state) do
    Logger.debug "Node #{state.node_id} handling status: #{payload}"

    new_state = %{state | status: payload}
    NodeUpdatedEvent.broadcast(new_state)

    {:noreply, new_state}
  end


  # Handle incoming messages
  def handle_info({:mysensors_message, message = %{child_sensor_id: sensor_id}}, state) do
    if Map.has_key?(state.sensors, sensor_id) do
      Sensor.on_event(state.sensors[sensor_id], message)
    else
      Logger.warn "Node #{state.node_id} handling unexpected event #{message}"
    end

    {:noreply, state}
  end


  # Handle unexpected messages
  def handle_info(msg, state) do
    Logger.warn "Node #{state.node_id} handling unexpected message #{inspect msg}"
    {:noreply, state}
  end



  defmodule NodeDiscoveredEvent do

    @moduledoc """
    An event generated when a new node is discovered
    """

    # Event struct
    defstruct node_id: nil, specs: nil

    @typedoc "The event struct"
    @type t :: %__MODULE__{node_id: Types.id, specs: MySensors.Node.t}


    @doc """
    Create a NodeDiscoveredEvent
    """
    @spec new(MySensors.Node.t) :: t
    def new(specs) do
      %__MODULE__{node_id: specs.node_id, specs: specs}
    end


    def broadcast(specs) do
      event = new(specs)
      Phoenix.PubSub.broadcast MySensors.PubSub, "nodes_events", {:mysensors, :node_event, event}
    end

  end


  defmodule NodeUpdatedEvent do

    @moduledoc """
    An event generated when a node is updated
    """

    # Event struct
    defstruct node_id: nil, specs: nil

    @typedoc "The event struct"
    @type t :: %__MODULE__{node_id: Types.id, specs: MySensors.Node.t}


    @doc """
    Create a NodeUpdatedEvent
    """
    @spec new(MySensors.Node.t) :: t
    def new(specs) do
      %__MODULE__{node_id: specs.node_id, specs: specs}
    end


    def broadcast(specs) do
      event = new(specs)
      Phoenix.PubSub.broadcast MySensors.PubSub, "nodes_events", {:mysensors, :node_event, event}
    end

  end

end
