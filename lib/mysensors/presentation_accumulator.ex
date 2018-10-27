defmodule MySensors.PresentationAccumulator do
  alias MySensors.Types
  alias MySensors.Node

  @moduledoc "A server accumulating presentation events"
  use GenServer

  @timeout 1000

  @doc "Start the accumulator"
  @spec start_link(Types.id(), String.t(), String.t()) :: GenServer.on_start()
  def start_link(node_id, type \\ nil, version \\ nil), do: GenServer.start(__MODULE__, {node_id, type, version})

  # Initialize the accumulator
  def init({node_id, type, version}) do
    specs = %Node{
      node_id: node_id,
      type: type,
      version: version,
      sketch_name: nil,
      sketch_version: nil,
      sensors: %{}
    }

    {:ok, specs, @timeout}
  end

  # Handle presentation events
  def handle_info(msg = %{command: :internal}, state) do
    new_state =
      case msg.type do
        I_SKETCH_NAME -> %{state | sketch_name: msg.payload}
        I_SKETCH_VERSION -> %{state | sketch_version: msg.payload}
        _ -> state
      end

    {:noreply, new_state, @timeout}
  end

  # Handle presentation events
  def handle_info(msg = %{command: :presentation}, state) do
    new_state =
      case msg.child_sensor_id do
        255 ->
          %{state | type: msg.type, version: msg.payload}

        # Skip the NodeManager CUSTOM sensor (status is handled internally by `MySensors.Node`)
        200 ->
          state

        sensor_id ->
          %{
            state
            | sensors: Map.put(state.sensors, sensor_id, {sensor_id, msg.type, msg.payload})
          }
      end

    {:noreply, new_state, @timeout}
  end

  # Handle timeout to shutdown the accumulator
  def handle_info(:timeout, state) do
    {:stop, {:shutdown, state}, state}
  end
end

