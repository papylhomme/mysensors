defmodule MySensors.Gateway do

  alias MySensors.Types
  alias MySensors.Message

  @moduledoc """
  A server handling communication with MySensors Serial Gateway

  TODO handle acks
  """


  use GenServer

  require Logger


  @doc """
  Start the server on the given serial device
  """
  @spec start_link(String.t) :: GenServer.on_start
  def start_link(serial_dev) do
    GenServer.start_link(__MODULE__, serial_dev, name: __MODULE__)
  end


  @doc """
  DEV simulate a message from the gateway

  The message is injected directly in the pipeline using `Kernel.send/2`
  """
  @spec simulate(Message.t) :: :ok
  def simulate(msg) do
    send __MODULE__, {:nerves_uart, Application.get_env(:mysensors, :uart), msg}
    :ok
  end


  @doc """
  Send a message via the gateway
  """
  @spec send_message(Message.t) :: :ok
  def send_message(message) do
    GenServer.cast(__MODULE__, {:send, message})
  end


  @doc """
  Send a message via the gateway
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


  # Initialize the serial connection at server startup
  def init(serial_dev) do
    Logger.debug "Starting MySensors serial gateway on #{serial_dev}"
    #:ok = Nerves.UART.open(Nerves.UART, serial_dev, speed: 115200, active: true, framing: {Nerves.UART.Framing.Line, separator: "\n"})
    Nerves.UART.open(Nerves.UART, serial_dev, speed: 115200, active: true, framing: {Nerves.UART.Framing.Line, separator: "\n"})

    {:ok, %{serial_dev: serial_dev}}
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
  def handle_info(msg = {:nerves_uart, _, _}, state) do
    serial_dev = state.serial_dev
    case msg do
      {:nerves_uart, ^serial_dev, {:error, e}} ->
        Logger.error "Unable to open UART: #{inspect e}"

      {:nerves_uart, ^serial_dev, str} ->
        #TODO handle errors
        str
        |> MySensors.Message.parse
        |> _process_message

      _ ->
        Logger.warn "Unknown message: #{inspect msg}"
    end

    {:noreply, state}
  end


  # Fallback for unknown messages
  def handle_info(msg, state) do
    Logger.warn "Unknown message: #{inspect msg}"
    {:noreply, state}
  end


  # Handle gateway ready
  defp _process_message(%{command: :internal, type: I_GATEWAY_READY}) do
    Logger.info "Gateway ready !"
  end


  # Process a presentation message
  defp _process_message(msg = %{command: :presentation}) do
    Logger.debug "Presentation event #{msg}"
    MySensors.PresentationManager.on_presentation_event(msg)
  end


  # Process a set message
  defp _process_message(msg = %{command: :set}) do
    Logger.debug "Node event #{msg}"
    MySensors.NodeManager.on_node_event(msg)
  end


  # Log from the gateway
  defp _process_message(msg = %{command: :internal, type: I_LOG_MESSAGE}) do
    Logger.debug "GWLOG #{msg.payload}"
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


  # Fallback for internal commands
  defp _process_message(msg = %{command: :internal}) do
    Logger.debug "Internal event #{msg}"
  end


  # Process an error message
  defp _process_message({:error, input, e, stacktrace}) do
    Logger.error "Error processing input '#{input}': #{inspect e}\n#{stacktrace |> Exception.format_stacktrace}"
  end


  # Process an unknown message
  defp _process_message(msg) do
    Logger.warn "Unknown event #{inspect msg}"
  end


  # Send a message to the gateway
  defp _send_message(msg) do
    s = MySensors.Message.serialize(msg)

    Logger.debug fn -> "Sending message #{msg}-> RAW: #{s}" end
    Nerves.UART.write(Nerves.UART, "#{s}\n")
  end


  # Construct and send a message to the gateway
  defp _send_message(node_id, child_sensor_id, command, ack, type, payload \\ "") do
    MySensors.Message.new(node_id, child_sensor_id, command, ack, type, payload)
    |> _send_message
  end

end

