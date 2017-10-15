defmodule MySensors.Sensor do

  @moduledoc """
  A server to interract with a MySensors sensor
  """

  use GenServer

  require Logger


  @doc """
  Start the server
  """
  def start_link(node_id, sensor_specs = {sensor_id, _, _}) do
    GenServer.start_link(__MODULE__, {node_id, sensor_specs}, [name: "#{MySensors.Node}#{node_id}.Sensor#{sensor_id}" |> String.to_atom])
  end


  @doc """
  Request information about the sensor
  """
  def info(pid) do
    GenServer.call(pid, :info)
  end


  @doc """
  Request data
  """
  def data(pid) do
    GenServer.call(pid, :data)
  end


  @doc """
  Request data
  """
  def data(pid, type) do
    GenServer.call(pid, {:data, type})
  end


  @doc """
  Send a command to the sensor
  """
  def command(pid, command, ack \\ false, type, payload \\ "") do
    GenServer.cast(pid, {:sensor_command, command, ack, type, payload})
  end


  @doc """
  Handle a node event
  """
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
    {:noreply, put_in(state, [:data, type], {value, DateTime.utc_now})}
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
