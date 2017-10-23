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
  @spec start_link() :: GenServer.on_start
  def start_link() do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end


  @doc """
  Request the node for presentation
  """
  @spec request_presentation(Types.id) :: :ok
  def request_presentation(node) do
    :ok = GenServer.cast(__MODULE__, {:request_presentation, node})
  end




  @doc """
  Process a presentation event
  """
  @spec on_presentation_event(MySensors.Message.presentation) :: :ok
  def on_presentation_event(msg) do
    GenServer.cast(__MODULE__, msg)
  end


  # Initialize the manager
  def init(:ok) do
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

    Map.get(new_state, node) |> Accumulator.on_presentation_event(msg)

    {:noreply, new_state}
  end


  # Handle presentation event
  def handle_cast(msg = %{node_id: node}, state) do
    case Map.has_key?(state, node) do
      false -> Logger.error "No presentation running for node #{node} #{inspect state}"
      true -> Map.get(state, node) |> Accumulator.on_presentation_event(msg)
    end

    {:noreply, state}
  end


  # Handle accumulator finishing
  # TODO update only of the accumulator is not empty/unused
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
      {:ok, pid} = Accumulator.start_link(node, type, version)
      Process.monitor(pid)

      put_in(state, [node], pid)
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
    @spec start_link(Types.id, String.t, String.t) :: GenServer.on_start
    def start_link(node_id, type \\ nil, version \\ nil) do
      GenServer.start(__MODULE__, {node_id, type, version})
    end


    @doc """
    Process a presentation event
    """
    @spec on_presentation_event(pid, MySensors.Message.presentation) :: :ok
    def on_presentation_event(pid, msg) do
      GenServer.cast(pid, msg)
    end


    # Initialize the accumulator
    def init({node_id, type, version}) do
      state = %Node{
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
      {:noreply, %Node{state | sketch_name: sketch_name}, @timeout}
    end


    # Handle the sketch version
    def handle_cast(%{command: :internal, type: I_SKETCH_VERSION, payload: sketch_version}, state) do
      {:noreply, %Node{state | sketch_version: sketch_version}, @timeout}
    end


    # Handle the node presentation event
    def handle_cast(%{command: :presentation, child_sensor_id: 255, type: type, payload: version}, state) do
      {:noreply, %Node{state | type: type, version: version}, @timeout}
    end


    # Handle a sensor presentation event
    def handle_cast(%{command: :presentation, child_sensor_id: sensor_id, type: sensor_type, payload: sensor_desc}, state) do
      sensors = Map.put(state.sensors, sensor_id, {sensor_id, sensor_type, sensor_desc})

      {:noreply, %Node{state | sensors: sensors}, @timeout}
    end


    # Handle timeout to shutdown the accumulator
    def handle_info(:timeout, state) do
      {:stop, {:shutdown, state}, state}
    end

  end

end
