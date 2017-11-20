defmodule MySensors.Gateway do

  alias MySensors.Types
  alias MySensors.Message

  @moduledoc """
  A server handling communication with a [MySensors Serial Gateway](https://www.mysensors.org/build/serial_gateway)

  In case the serial device is not present when starting, the server checks
  regularly to reconnect if possible. It also handles gracefuly disconnection
  and reconnect when the device is back.

  TODO handle acks
  """


  use GenServer
  require Logger


  @retry_timeout 5000


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
    Logger.info "Starting MySensors serial gateway on #{serial_dev}"

    case _try_connect(serial_dev) do
      :ok -> {:ok, %{serial_dev: serial_dev, status: :connected}}
      _   -> {:ok, %{serial_dev: serial_dev, status: :disconnected}, @retry_timeout}
    end
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


  # Handle timeout to reconnect the UART
  def handle_info(:timeout, state = %{status: :disconnected, serial_dev: serial_dev}) do
    case _try_connect(serial_dev) do
      :ok -> {:noreply, %{state | status: :connected}}
      _   -> {:noreply, state, @retry_timeout}
    end
  end


  # Handle UART closed message
  def handle_info({:nerves_uart, _, {:error, :eio}}, state) do
    Logger.warn "UART closed !"
    {:noreply, %{state | status: :disconnected}, @retry_timeout}
  end


  # Handle incoming messages
  def handle_info(msg = {:nerves_uart, _, _}, state = %{serial_dev: serial_dev}) do
    case msg do
      # error
      {:nerves_uart, ^serial_dev, {:error, e}} ->
        Logger.error "UART error: #{inspect e}"

      # message received
      {:nerves_uart, ^serial_dev, str} ->
        #TODO handle errors
        str
        |> MySensors.Message.parse
        |> _process_message


      # unknown message
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


  # Try to connect to the serial gateway
  defp _try_connect(serial_dev) do
    case Map.has_key?(Nerves.UART.enumerate(), serial_dev) do
      false ->
        Logger.debug "Serial device #{serial_dev} not present, will retry later"
        :not_present

      true  ->
        case Nerves.UART.open(Nerves.UART, serial_dev, speed: 115200, active: true, framing: {Nerves.UART.Framing.Line, separator: "\n"}) do
          :ok ->
            Logger.info "Connected to serial device #{serial_dev}"
            :ok

          {:error, reason} ->
            Logger.error "Error connecting to serial device #{serial_dev}: #{inspect reason}"
            :error
        end
    end
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

