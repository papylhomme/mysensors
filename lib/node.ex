defmodule MySensors.Node do

  @moduledoc """
  A server to interract with a MySensors node

  TODO support offline/online/lastseen/heartbeat and such
  """

  use GenServer

  require Logger


  @doc """
  Start the server
  """
  def start_link({table, node_id}) do
    GenServer.start_link(__MODULE__, {table, node_id}, [name: "#{MySensors.Node}#{node_id}" |> String.to_atom])
  end


  @doc """
  Request information about the node
  """
  def info(pid) do
    GenServer.call(pid, :info)
  end


  @doc """
  List the sensors
  """
  def sensors(pid) do
    GenServer.call(pid, :list_sensors)
  end


  @doc """
  Handle a node event
  """
  def on_event(pid, msg) do
    GenServer.cast(pid, {:node_event, msg})
  end


  # Initialize the server
  def init({table, node_id}) do
    [{_id, node_specs}] = :dets.lookup(table, node_id)

    sensors =
      for {id, sensor_specs} <- node_specs.sensors, into: %{} do
        {:ok, pid} = MySensors.Sensor.start_link(node_specs.node_id, sensor_specs)
        {id, pid}
      end

    Logger.info "New node #{node_specs.node_id} online (#{inspect node_specs.sensors})"

    {:ok, %{
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
        MySensors.Sensor.info(pid)
      end)

    {:reply, res, state}
  end


  # Handle node events
  def handle_cast({:node_event, msg = %{child_sensor_id: sensor_id}}, state) do
    if Map.has_key?(state.sensors, sensor_id) do
      MySensors.Sensor.on_event(state.sensors[sensor_id], msg)
    else
      Logger.warn "Node #{state.node_id} handling unexpected event #{msg}"
    end

    {:noreply, state}
  end

end
