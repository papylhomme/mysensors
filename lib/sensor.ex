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
    {:ok, %{node_id: node_id, id: id, type: type, desc: desc}}
  end


  # Handle info request
  def handle_call(:info, _from, state) do
    {:reply, state, state}
  end


  # Handle sensor commands
  def handle_cast({:sensor_command, command, ack, type, payload}, state) do
    MySensors.Message.new(state.node_id, state.id, command, ack, type, payload)
    |> MySensors.Gateway.send_message

    {:noreply, state}
  end


  # Handle sensor events
  def handle_cast({:sensor_event, msg}, state) do
    Logger.warn "Node#{state.node_id}/Sensor#{state.id} (#{state.type}) handling event #{msg}"
    {:noreply, state}
  end

end
