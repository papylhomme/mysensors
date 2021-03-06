defmodule MySensors.Sensor do
  alias MySensors.Types

  alias __MODULE__
  alias __MODULE__.ValueUpdatedEvent

  @moduledoc """
  A server to interract with a MySensors sensor
  """

  # The sensor struct
  defstruct uuid: nil, node: nil, sensor_id: nil, type: nil, desc: nil, data: %{}

  @typedoc "A sensor specs"
  @type specs :: {Types.id(), Types.sensor(), String.t()}

  @typedoc "Data tuple"
  @type data :: {any, DateTime.t()}

  @typedoc "Datas map"
  @type datas :: %{optional(Types.variable()) => data}

  @typedoc "Sensor's info"
  @type t :: %__MODULE__{
          uuid: String.t(),
          node: String.t(),
          sensor_id: Types.id(),
          type: Types.sensor(),
          desc: String.t(),
          data: datas
        }

  use GenServer
  use MySensors.PubSub

  require Logger

  #########
  #  API
  #########


  @doc "Start the server"
  @spec start_link(String.t, pid, specs) :: GenServer.on_start()
  def start_link(uuid, node, sensor_specs), do: GenServer.start_link(__MODULE__, {uuid, node, sensor_specs}, name: MySensors.by_uuid(uuid))

  @doc "Get information about the sensor"
  @spec info(pid) :: t
  def info(pid), do: GenServer.call(pid, :info)

  @doc "Get all available datas"
  @spec data(pid) :: datas
  def data(pid), do: GenServer.call(pid, :data)

  @doc "Get data for the given variable type"
  @spec data(pid, Types.variable()) :: data
  def data(pid, type), do: GenServer.call(pid, {:data, type})

  @doc "Send a command to the sensor"
  @spec command(pid, Types.command(), Types.type(), String.t()) :: :ok
  def command(pid, command, type, payload \\ ""), do: GenServer.cast(pid, {:sensor_command, command, type, payload})

  @doc "Handle a sensor event asynchronously"
  @spec on_event(pid, MySensors.Message.sensor_updated()) :: :ok
  def on_event(pid, msg), do: GenServer.cast(pid, {:sensor_event, msg})


  ############
  #  Events
  ############

  topic_helpers(MySensors.Bus, :sensors_events, fn sensor_uuid -> "sensor_#{sensor_uuid}_events" end, "sensors_events")


  defmodule ValueUpdatedEvent do
    @moduledoc "An event generated when a sensor updates one of its values"
    defstruct sensor: nil, type: nil, old: nil, new: {nil, nil}

    @typedoc "The value updated event struct"
    @type t :: %__MODULE__{
            sensor: String.t(),
            type: Types.type(),
            old: nil | Sensor.data(),
            new: Sensor.data()
          }

    @doc "Create and broadcast a ValueUpdatedEvent from a MySensors sensor update event"
    @spec broadcast(MySensors.Message.sensor_updated(), Sensor.t(), Sensor.data(), Sensor.data()) :: t
    def broadcast(mysensors_event, sensor, old_value, new_value) do
      e = %__MODULE__{sensor: sensor.uuid, type: mysensors_event.type, old: old_value, new: new_value}
      Sensor.broadcast_sensors_events(sensor.uuid, e)
    end
  end


  ##############################
  #  GenServer Implementation
  ##############################

  # Initialize the server
  def init({uuid, node, {sensor_id, type, desc}}) do
    {:ok, %__MODULE__{uuid: uuid, node: node, sensor_id: sensor_id, type: type, desc: desc, data: %{}}}
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
    MySensors.Node.command(MySensors.by_uuid(state.node), state.sensor_id, command, type, payload)
    {:noreply, state}
  end

  # Handle sensor values
  def handle_cast({:sensor_event, event = %{command: :set, type: type, payload: value}}, state) do
    Logger.debug("#{_sensor_name(state)} received new #{type} value: #{value}")

    old_value = Map.get(state.data, type)
    new_value = {value, DateTime.utc_now()}
    data = Map.put(state.data, type, new_value)

    event
    |> ValueUpdatedEvent.broadcast(state, old_value, new_value)

    {:noreply, %__MODULE__{state | data: data}}
  end

  # Handle other sensor events
  def handle_cast({:sensor_event, msg}, state) do
    Logger.warn("#{_sensor_name(state)} received unexpected event: #{msg}")
    {:noreply, state}
  end


  ###############
  #  Internals
  ###############

  # Create a readable sensor name
  # TODO multi fix this or remove
  defp _sensor_name(state) do
    "Sensor #{state.uuid} (#{state.type})"
  end


end
