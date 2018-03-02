defmodule MySensors.PresentationManager do
  alias MySensors.Types
  alias __MODULE__.Accumulator

  @moduledoc """
  A manager for presentation related events
  """

  use GenServer, start: {__MODULE__, :start_link, []}

  require Logger

  @doc """
  Start the manager
  """
  @spec start_link() :: GenServer.on_start()
  def start_link() do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @doc """
  Request the node for presentation
  """
  @spec request_presentation(Types.id()) :: :ok
  def request_presentation(node) do
    :ok = GenServer.cast(__MODULE__, {:request_presentation, node})
  end


  # Initialize the manager
  def init(:ok) do
    MySensors.Bus.subscribe("presentation")
    MySensors.Bus.subscribe("internal")

    {:ok, %{}}
  end

  # Handle request presentation call
  def handle_cast({:request_presentation, node}, state) do
    new_state =
      case Map.has_key?(state, node) do
        true ->
          Logger.warn("Presentation request already running for node #{node}!")
          state

        false ->
          Logger.info("Requesting presentation from node #{node}...")

          :ok = MySensors.Gateway.send_message(node, 255, :internal, I_PRESENTATION)
          state |> _init_accumulator(node)
      end

    {:noreply, new_state}
  end

  # Forward presentation messages
  def handle_info({"presentation", msg = %{command: :presentation}}, state) do
    {:noreply, _forward_presentation(state, msg)}
  end

  # Forward sketch info messages
  def handle_info({"internal", msg = %{child_sensor_id: 255, command: :internal, type: t}}, state) when t in [I_SKETCH_NAME, I_SKETCH_VERSION] do
    {:noreply, _forward_presentation(state, msg)}
  end

  # Discard remaining internal messages
  def handle_info({"internal", _msg = %{command: :internal}}, state) do
    {:noreply, state}
  end

  # Handle accumulator finishing
  def handle_info({:DOWN, _, _, _, {:shutdown, acc}}, state) do
    case _accumulator_ready?(acc) do
      false ->
        Logger.debug("Discarding empty accumulator for node #{acc.node_id} #{inspect acc}")

      true ->
        Logger.debug(
          "Presentation accumulator for node #{acc.node_id} finishing #{inspect acc}"
        )

        :ok = MySensors.NodeManager.on_node_presentation(acc)
    end

    {:noreply, Map.delete(state, acc.node_id)}
  end

  # Fallback for handle_info
  def handle_info(msg, state) do
    Logger.warn("Received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  # Initialize an accumulator for the given node
  defp _init_accumulator(state, node, type \\ nil, version \\ nil) do
    {:ok, pid} = Accumulator.start_link(node, type, version)
    Process.monitor(pid)

    put_in(state, [node], pid)
  end

  # Forward a presentation event to its related accumulator, creating a new one if needed
  defp _forward_presentation(state, msg = %{node_id: node}) do
    new_state =
      case Map.has_key?(state, node) do
        true -> state
        false -> state |> _init_accumulator(node)
      end

    Map.get(new_state, node) |> Accumulator.on_presentation_event(msg)
    new_state
  end

  # Test if an accumulator has received sufficient information
  defp _accumulator_ready?(acc) do
    not(is_nil(acc.node_id) or is_nil(acc.type) or(map_size(acc.sensors) == 0))
  end


  defmodule Accumulator do
    alias MySensors.Node

    @moduledoc """
    An accumulator for presentation events
    """

    use GenServer

    @timeout 1000

    @doc """
    Start the accumulator
    """
    @spec start_link(Types.id(), String.t(), String.t()) :: GenServer.on_start()
    def start_link(node_id, type \\ nil, version \\ nil) do
      GenServer.start(__MODULE__, {node_id, type, version})
    end

    @doc """
    Process a presentation event
    """
    @spec on_presentation_event(pid, MySensors.Message.presentation()) :: :ok
    def on_presentation_event(pid, msg) do
      GenServer.cast(pid, msg)
    end

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

    # Handle the sketch name
    def handle_cast(%{command: :internal, type: I_SKETCH_NAME, payload: sketch_name}, state) do
      {:noreply, %{state | sketch_name: sketch_name},
       @timeout}
    end

    # Handle the sketch version
    def handle_cast(%{command: :internal, type: I_SKETCH_VERSION, payload: sketch_version}, state) do
      {:noreply,
       %{state | sketch_version: sketch_version},
       @timeout}
    end

    # Handle the node presentation event
    def handle_cast(
          %{command: :presentation, child_sensor_id: 255, type: type, payload: version},
          state
        ) do
      {:noreply,
       %{state | type: type, version: version},
       @timeout}
    end

    # Skip the NodeManager CUSTOM sensor (status is handled internally by `MySensors.Node`)
    def handle_cast(%{command: :presentation, child_sensor_id: 200, type: S_CUSTOM}, state) do
      {:noreply, state, @timeout}
    end

    # Handle a sensor presentation event
    def handle_cast(
          %{
            command: :presentation,
            child_sensor_id: sensor_id,
            type: sensor_type,
            payload: sensor_desc
          },
          state
        ) do
      sensors = Map.put(state.sensors, sensor_id, {sensor_id, sensor_type, sensor_desc})

      {:noreply, %{state | sensors: sensors}, @timeout}
    end

    # Handle timeout to shutdown the accumulator
    def handle_info(:timeout, state) do
      {:stop, {:shutdown, state}, state}
    end
  end
end
