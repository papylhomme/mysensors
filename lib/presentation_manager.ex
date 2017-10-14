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
  Request the node for presentation
  """
  def request_presentation(node) do
    :ok = GenServer.cast(__MODULE__, {:request_presentation, node})
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


  # Handle version call
  def handle_cast({:request_presentation, node}, state) do
    new_state =
      case Map.has_key?(state, node) do
        true ->
          Logger.warn "Presentation request already running for node #{node}!"
          state

        false ->
          Logger.info "Requesting presentation from node #{node}..."

          :ok = MySensors.Gateway.send_message(node, 255, :internal, false, I_PRESENTATION)
          state |> _init_accumulator(node)
      end

    {:noreply, new_state}
  end


  # Handle receiving presentation without asking first
  def handle_cast(msg = %{node_id: node, child_sensor_id: 255, command: :presentation}, state) do
    new_state =
      case Map.has_key?(state, node) do
        true -> state
        false -> state |> _init_accumulator(node)
      end

    Map.get(new_state, node) |> PresentationAccumulator.on_presentation_event(msg)

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
    Logger.debug "Presentation accumulator for node #{acc.node_id} finishing #{inspect acc}"
    :ok = MySensors.NodeManager.on_node_presentation(acc)
    {:noreply, Map.delete(state, acc.node_id)}
  end


  # Fallback for handle_info
  def handle_info(_, state) do
    {:noreply, state}
  end


  # Initialize an accumulator for the given node
  defp _init_accumulator(state, node, type \\ nil, version \\ nil) do
      {:ok, pid} = PresentationAccumulator.start_link(node, type, version)
      Process.monitor(pid)

      put_in(state, [node], pid)
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
    def start_link(node_id, type \\ nil, version \\ nil) do
      GenServer.start(__MODULE__, {node_id, type, version})
    end

    @doc """
    Process a presentation event
    """
    def on_presentation_event(pid, msg) do
      GenServer.cast(pid, msg)
    end


    # Initialize the accumulator
    def init({node_id, type, version}) do
      state = %{
        node_id: node_id,
        type: type,
        version: version,
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


    # Handle the node presentation event
    def handle_cast(%{command: :presentation, child_sensor_id: 255, type: type, payload: version}, state) do
      {:noreply, %{state | type: type, version: version}, @timeout}
    end


    # Handle a sensor presentation event
    def handle_cast(%{command: :presentation, child_sensor_id: sensor_id, type: sensor_type, payload: sensor_desc}, state) do
      {:noreply, put_in(state, [:sensors, sensor_id], {sensor_id, sensor_type, sensor_desc}), @timeout}
    end


    # Handle timeout to shutdown the accumulator
    def handle_info(:timeout, state) do
      {:stop, {:shutdown, state}, state}
    end

  end

end
