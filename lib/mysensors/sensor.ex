defmodule MySensors.Sensor do
  alias MySensors.Types
  alias MySensors.Bus
  alias __MODULE__.ValueUpdatedEvent

  @moduledoc """
  A server to interract with a MySensors sensor
  """

  # The sensor struct
  defstruct id: nil, node_id: nil, type: nil, desc: nil, data: %{}

  @typedoc "A sensor specs"
  @type specs :: {Types.id(), Types.sensor(), String.t()}

  @typedoc "Data tuple"
  @type data :: {any, DateTime.t()}

  @typedoc "Datas map"
  @type datas :: %{optional(Types.variable()) => data}

  @typedoc "Sensor's info"
  @type t :: %__MODULE__{
          id: Types.id(),
          node_id: Types.id(),
          type: Types.sensor(),
          desc: String.t(),
          data: datas
        }

  use GenServer
  require Logger

  #########
  #  API
  #########

  @doc """
  Helper generating an unique reference for the given node/sensor ids
  """
  @spec ref(Types.id(), Types.id()) :: atom
  def ref(node_id, child_sensor_id) do
    "#{MySensors.Node}#{node_id}.Sensor#{child_sensor_id}" |> String.to_atom()
  end

  @doc """
  Start the server
  """
  @spec start_link(Types.id(), specs) :: GenServer.on_start()
  def start_link(node_id, sensor_specs = {sensor_id, _, _}) do
    GenServer.start_link(__MODULE__, {node_id, sensor_specs}, name: ref(node_id, sensor_id))
  end

  @doc """
  Get information about the sensor
  """
  @spec info(pid) :: t
  def info(pid) do
    GenServer.call(pid, :info)
  end

  @doc """
  Get all available datas
  """
  @spec data(pid) :: datas
  def data(pid) do
    GenServer.call(pid, :data)
  end

  @doc """
  Get data for the given variable type
  """
  @spec data(pid, Types.variable()) :: data
  def data(pid, type) do
    GenServer.call(pid, {:data, type})
  end

  @doc """
  Send a command to the sensor
  """
  @spec command(pid, Types.command(), Types.type(), String.t()) :: :ok
  def command(pid, command, type, payload \\ "") do
    GenServer.cast(pid, {:sensor_command, command, type, payload})
  end

  @doc """
  Handle a sensor event asynchronously
  """
  @spec on_event(pid, MySensors.Message.sensor_updated()) :: :ok
  def on_event(pid, msg) do
    GenServer.cast(pid, {:sensor_event, msg})
  end

  ###############
  #  Internals
  ###############

  # Initialize the server
  def init({node_id, {id, type, desc}}) do
    {:ok, %__MODULE__{node_id: node_id, id: id, type: type, desc: desc, data: %{}}}
  end

  # Handle info request
  def handle_call(:info, _from, state) do
    {:reply, state, state}
  end

  # Handle data request
  def handle_call(:data, _from, state) do
    {:reply, state.data, state}
  end

  # Handle data request
  def handle_call({:data, type}, _from, state) do
    {:reply, Map.get(state.data, type), state}
  end

  # Handle sensor commands
  def handle_cast({:sensor_command, command, type, payload}, state) do
    MySensors.Node.ref(state.node_id)
    |> MySensors.Node.command(state.id, command, type, payload)

    {:noreply, state}
  end

  # Handle sensor values
  def handle_cast({:sensor_event, event = %{command: :set, type: type, payload: value}}, state) do
    Logger.debug("#{_sensor_name(state)} received new #{type} value: #{value}")

    old_value = Map.get(state.data, type)

    new_value = {value, DateTime.utc_now()}
    data = Map.put(state.data, type, new_value)

    event
    |> ValueUpdatedEvent.broadcast(old_value, new_value)

    {:noreply, %__MODULE__{state | data: data}}
  end

  # Handle other sensor events
  def handle_cast({:sensor_event, msg}, state) do
    Logger.warn("#{_sensor_name(state)} received unexpected event: #{msg}")
    {:noreply, state}
  end

  # Create a readable sensor name
  defp _sensor_name(state) do
    "Sensor #{state.node_id}##{state.id} (#{state.type})"
  end

  defmodule ValueUpdatedEvent do
    alias MySensors.Sensor

    @moduledoc """
    An event generated when a sensor updates one of its values
    """

    # Event struct
    defstruct node_id: nil, sensor_id: nil, type: nil, old: nil, new: {nil, nil}

    @typedoc "The value updated event struct"
    @type t :: %__MODULE__{
            node_id: Types.id(),
            sensor_id: Types.id(),
            type: Types.type(),
            old: nil | Sensor.data(),
            new: Sensor.data()
          }

    @doc """
    Create a ValueUpdatedEvent from a MySensors sensor update event
    """
    @spec new(MySensors.Message.sensor_updated(), Sensor.data(), Sensor.data()) :: t
    def new(mysensors_event, old_value, new_value) do
      %__MODULE__{
        node_id: mysensors_event.node_id,
        sensor_id: mysensors_event.child_sensor_id,
        type: mysensors_event.type,
        old: old_value,
        new: new_value
      }
    end

    def broadcast(mysensors_event, old_value, new_value) do
      new(mysensors_event, old_value, new_value)
      |> Bus.broadcast_sensors_events()
    end
  end
end
