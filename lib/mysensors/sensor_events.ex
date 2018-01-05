defmodule MySensors.SensorEvents do

  alias MySensors.Sensor


  @moduledoc """
  An event dispatcher for sensor events built with `MySensors.PubSub`
  """

  use MySensors.PubSub


  @doc """
  Dispatches a sensor `event`
  """
  @spec on_sensor_event(Sensor.ValueUpdatedEvent.t) :: :ok
  def on_sensor_event(event = %{node_id: node_id, sensor_id: sensor_id}) do
    dispatch_event(@registry, {node_id, sensor_id}, event)
  end


  @doc """
  Registers a global event handler
  """
  @spec register_sensors_handler() :: :ok
  def register_sensors_handler do
    register(@registry, :global)
  end


  @doc """
  Unregisters a global event handler
  """
  @spec unregister_sensors_handler() :: :ok
  def unregister_sensors_handler do
    unregister(@registry, :global)
  end


  @doc """
  Registers as event handler of the given `sensors`

  As a convenience, `sensors` can be a list or a single element.
  """
  @spec register_sensors_handler(Sensor.t | [Sensor.t]) :: :ok
  def register_sensors_handler(sensors) when is_list(sensors) do
    Enum.each(sensors, fn sensor -> register_sensors_handler(sensor) end)
  end

  def register_sensors_handler(_sensor = %{node_id: node_id, id: sensor_id}) do
    register(@registry, {node_id, sensor_id})
  end


  @doc """
  Unregisters as event handler from the given `sensors`

  As a convenience, `sensors` can be a list or a single element.
  """
  @spec unregister_sensors_handler(Sensor.t | [Sensor.t]) :: :ok
  def unregister_sensors_handler(sensors) when is_list(sensors) do
    Enum.each(sensors, fn sensor -> unregister_sensors_handler(sensor) end)
  end

  def unregister_sensors_handler(_sensor = %{node_id: node_id, id: sensor_id}) do
    unregister(@registry, {node_id, sensor_id})
  end

end
