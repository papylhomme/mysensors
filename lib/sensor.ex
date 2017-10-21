defmodule MySensors.Sensor do

  alias MySensors.Types

  @moduledoc """
  A server to interract with a MySensors sensor
  """

  defstruct id: nil, node_id: nil, type: nil, desc: nil, data: %{}

  @typedoc "A sensor specs"
  @type specs :: {Types.id, Types.sensor, String.t}

  @typedoc "Data tuple"
  @type data :: {any, DateTime.t}

  @typedoc "Datas map"
  @type datas :: %{optional(Types.variable) => data}

  @typedoc "Sensor's info"
  @type t :: %__MODULE__{id: Types.id, node_id: Types.id, type: Types.sensor, desc: String.t, data: datas}


  use GenServer
  require Logger



  @doc """
  Start the server
  """
  @spec start_link(Types.id, specs) :: GenServer.on_start
  def start_link(node_id, sensor_specs = {sensor_id, _, _}) do
    GenServer.start_link(__MODULE__, {node_id, sensor_specs}, [name: "#{MySensors.Node}#{node_id}.Sensor#{sensor_id}" |> String.to_atom])
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
  @spec data(pid, Types.variable) :: data
  def data(pid, type) do
    GenServer.call(pid, {:data, type})
  end


  @doc """
  Send a command to the sensor asynchronously
  """
  @spec command(pid, Types.command, boolean, Types.type, String.t) :: :ok
  def command(pid, command, ack \\ false, type, payload \\ "") do
    GenServer.cast(pid, {:sensor_command, command, ack, type, payload})
  end


  @doc """
  Handle a sensor event asynchronously
  """
  @spec on_event(pid, MySensors.Message.sensor_updated) :: :ok
  def on_event(pid, msg) do
    GenServer.cast(pid, {:sensor_event, msg})
  end



  # Initialize the server
  def init({node_id, {id, type, desc}}) do
    {:ok, %{node_id: node_id, id: id, type: type, desc: desc, data: %{}}}
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
  def handle_cast({:sensor_command, command, ack, type, payload}, state) do
    MySensors.Message.new(state.node_id, state.id, command, ack, type, payload)
    |> MySensors.Gateway.send_message

    {:noreply, state}
  end


  # Handle sensor values
  def handle_cast({:sensor_event, %{command: :set, type: type, payload: value}}, state) do
    Logger.debug "#{_sensor_name(state)} received new #{type} value: #{value}"

    data = put_in(state.data, type, {value, DateTime.utc_now})
    {:noreply, %__MODULE__{state | data: data}}
  end


  # Handle other sensor events
  def handle_cast({:sensor_event, msg}, state) do
    Logger.warn "#{_sensor_name(state)} received unexpected event: #{msg}"
    {:noreply, state}
  end


  # Create a readable sensor name
  defp _sensor_name(state) do
    "Node#{state.node_id}/Sensor#{state.id} (#{state.type})"
  end

end
