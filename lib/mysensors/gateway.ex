defmodule MySensors.Gateway do

  alias MySensors.Types
  alias MySensors.Message

  @moduledoc """
  A server handling communication with a [MySensors Gateway](https://www.mysensors.org/download/serial_api_20)

  **TODO**

  - handle acks
  """


  use GenServer, start: {__MODULE__, :start_link, []}
  require Logger


  #########
  #  API
  #########


  @doc """
  Start the server on the given serial device
  """
  @spec start_link :: GenServer.on_start
  def start_link do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end


  @doc """
  Send a message to the MySensors network
  """
  @spec send_message(Message.t) :: :ok
  def send_message(message) do
    GenServer.cast(__MODULE__, {:send, message})
  end


  @doc """
  Send a message to the MySensors network
  """
  @spec send_message(Types.id, Types.id, Types.command, boolean, Types.type, String.t) :: :ok
  def send_message(node_id, child_sensor_id, command, ack, type, payload \\ "") do
    message = MySensors.Message.new(node_id, child_sensor_id, command, ack, type, payload)
    GenServer.cast(__MODULE__, {:send, message})
  end


  @doc """
  Request gateway version
  """
  @spec version() :: :ok
  def version do
    :ok = GenServer.call(__MODULE__, {:version})
  end


  #################
  #   Internals   #
  #################


  # Init
  def init(nil) do
    Phoenix.PubSub.subscribe MySensors.PubSub, "incoming"
    {:ok, %{}}
  end


  # Handle version call
  def handle_call({:version}, _from, state) do
    {:reply, _send_message(0, 255, :internal, false, I_VERSION), state}
  end


  # Handle send message call
  def handle_cast({:send, message}, state) do
    _send_message(message)
    {:noreply, state}
  end


  # Handle incoming messages
  def handle_info({:mysensors_incoming, message}, state) do
    #Logger.debug "Received message: #{message}"
    _process_message(message)

    {:noreply, state}
  end


  # Fallback for unknown messages
  def handle_info(msg, state) do
    Logger.warn "Unknown message: #{inspect msg}"
    {:noreply, state}
  end


  # Process a presentation message
  defp _process_message(msg = %{command: :presentation}) do
    Logger.debug "Presentation event #{msg}"
    MySensors.PresentationManager.on_presentation_event(msg)
  end



  # Handle gateway ready
  defp _process_message(%{command: :internal, type: I_GATEWAY_READY}) do
    Logger.info "Gateway ready !"
  end


  # Log from the gateway
  defp _process_message(msg = %{command: :internal, type: I_LOG_MESSAGE}) do
    Phoenix.PubSub.broadcast MySensors.PubSub, "gwlog", {:mysensors_gwlog, msg.payload}
  end


  # Forward discover responses to the discovery manager
  defp _process_message(msg = %{command: :internal, type: I_DISCOVER_RESPONSE}) do
    Logger.debug "Discover response #{msg}"
    MySensors.DiscoveryManager.notify(msg)
  end


  # Process time requests
  defp _process_message(msg = %{command: :internal, type: I_TIME}) do
    Logger.debug "Requesting controller time #{msg}"
    _send_message(msg.node_id, msg.child_sensor_id, :internal, false, I_TIME, DateTime.utc_now |> DateTime.to_unix(:seconds))
  end


  # Process config requests
  defp _process_message(msg = %{command: :internal, type: I_CONFIG}) do
    Logger.debug "Requesting controller configuration #{msg}"

    payload =
      case Application.get_env(:mysensors, :measure) do
        :metric   -> "M"
        :imperial -> "I"
        _         -> ""
      end

    _send_message(msg.node_id, msg.child_sensor_id, :internal, false, I_CONFIG, payload)
  end


  # Forward sketch information to the presentation manager
  defp _process_message(msg = %{command: :internal, type: t}) when t in [I_SKETCH_NAME, I_SKETCH_VERSION] do
    Logger.debug "Sketch information event #{msg}"
    MySensors.PresentationManager.on_presentation_event(msg)
  end


  # Forward other message to their related node
  defp _process_message(msg = %{node_id: node_id}) do
    Phoenix.PubSub.broadcast MySensors.PubSub, "node_#{node_id}", {:mysensors_message, msg}
  end


  # Process an error message
  defp _process_message({:error, input, e, stacktrace}) do
    Logger.error "Error processing input '#{input}': #{inspect e}\n#{stacktrace |> Exception.format_stacktrace}"
  end


  # Process unexpected messages
  defp _process_message(msg) do
    Logger.debug "Unexpected message: #{inspect msg}"
  end


  # Construct and send a message to the gateway
  defp _send_message(node_id, child_sensor_id, command, ack, type, payload \\ "") do
    MySensors.Message.new(node_id, child_sensor_id, command, ack, type, payload)
    |> _send_message
  end


  # Send a message to the gateway
  defp _send_message(msg) do
    str = MySensors.Message.serialize(msg)

    Logger.debug fn -> "Sending message #{msg}-> RAW: #{str}" end
    Phoenix.PubSub.broadcast MySensors.PubSub, "outgoing", {:mysensors_outgoing, str}
  end


end

