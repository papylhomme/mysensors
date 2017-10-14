defmodule MySensors.PresentationManager do

  @moduledoc """
  A manager for presentation related events
  """

  use GenServer

  require Logger
  alias __MODULE__.PresentationAccumulator


  @doc """
  Start the manager
  """
  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end


  @doc """
  Process a presentation event
  """
  def on_presentation_event(msg) do
    GenServer.cast(__MODULE__, msg)
  end


  # Initialize the manager
  def init(_) do
    {:ok, %{}}
  end


  # Handle initial presentation message
  def handle_cast(msg = %{command: :presentation, child_sensor_id: 255, node_id: node}, state) do
    new_state =
      case Map.has_key?(state, node) do
        true ->
          Logger.error "Presentation for node #{node} is already running"
          state

        false ->
          Logger.info "Starting presentation accumulation for node #{node}"

          {:ok, pid} = PresentationAccumulator.start_link(msg)
          Process.monitor(pid)

          Map.put(state, node, pid)
      end

    {:noreply, new_state}
  end


  # Handle presentation event
  def handle_cast(msg = %{node_id: node}, state) do
    case Map.has_key?(state, node) do
      false -> Logger.error "No presentation running for node #{node} #{inspect state}"
      true -> Map.get(state, node) |> PresentationAccumulator.on_presentation_event(msg)
    end

    {:noreply, state}
  end


  # Handle accumulator finishing
  def handle_info({:DOWN, _, _, _, {:shutdown, acc}}, state) do
    Logger.info "Presentation accumulator finishing #{inspect acc}"
    {:noreply, Map.delete(state, acc.node_id)}
  end


  # Fallback for handle_info
  def handle_info(_, state) do
    {:noreply, state}
  end


  defmodule PresentationAccumulator do

    @moduledoc """
    An accumulator for presentation events
    """

    use GenServer

    @timeout 1000


    @doc """
    Start the accumulator
    """
    def start_link(initial_msg) do
      GenServer.start(__MODULE__, initial_msg)
    end


    @doc """
    Process a presentation event
    """
    def on_presentation_event(pid, msg) do
      GenServer.cast(pid, msg)
    end


    # Initialize the accumulator
    def init(initial_msg) do
      state = %{
        node_id: initial_msg.node_id,
        type: initial_msg.type,
        version: initial_msg.payload,
        sketch_name: nil,
        sketch_version: nil,
        sensors: %{}
      }

      {:ok, state, @timeout}
    end


    # Handle the sketch name
    def handle_cast(%{command: :internal, type: I_SKETCH_NAME, payload: sketch_name}, state) do
      {:noreply, %{state | sketch_name: sketch_name}}
    end


    # Handle the sketch version
    def handle_cast(%{command: :internal, type: I_SKETCH_VERSION, payload: sketch_version}, state) do
      {:noreply, %{state | sketch_version: sketch_version}}
    end


    # Handle a presentation event
    def handle_cast(%{command: :presentation, child_sensor_id: sensor_id, type: sensor_type, payload: sensor_desc}, state) do
      {:noreply, put_in(state, [:sensors, sensor_id], {sensor_id, sensor_type, sensor_desc}), @timeout}
    end


    # Handle timeout to shutdown the accumulator
    def handle_info(:timeout, state) do
      {:stop, {:shutdown, state}, state}
    end

  end

end
