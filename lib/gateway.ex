defmodule MySensors.Gateway do

  @moduledoc """
  A server handling communication with MySensors Serial Gateway

  TODO handle acks
  """


  use GenServer

  require Logger


  @doc """
  Start the server on the given serial device
  """
  def start_link(serial_dev) do
    GenServer.start_link(__MODULE__, serial_dev, name: __MODULE__)
  end


  @doc """
  DEV simulate a message from the gateway
  """
  def simulate(msg) do
    send __MODULE__, {:nerves_uart, Application.get_env(:mysensors, :uart), msg}
    :ok
  end


  @doc """
  Send a message to the gateway
  """
  def send_message(message) do
    :ok = GenServer.cast(__MODULE__, {:send, message})
  end


  @doc """
  Send a message to the gateway
  """
  def send_message(node_id, child_sensor_id, command, ack, type, payload \\ "") do
    message = MySensors.Message.new(node_id, child_sensor_id, command, ack, type, payload)
    :ok = GenServer.cast(__MODULE__, {:send, message})
  end



  @doc """
  Request gateway version
  """
  def version do
    :ok = GenServer.call(__MODULE__, {:version})
  end


  @doc """
  Discover nodes on the network
  """
  def discover do
    :ok = GenServer.call(__MODULE__, {:discover})
  end


  @doc """
  Discover sensors on the network and request presentation for each of them
  """
  def scan do
    :ok = GenServer.call(__MODULE__, {:scan})
  end





  #################
  #   Internals   #
  #################


  # Initialize the serial connection at server startup
  def init(serial_dev) do
    Logger.debug "Starting MySensors serial gateway on #{serial_dev}"
    :ok = Nerves.UART.open(Nerves.UART, serial_dev, speed: 115200, active: true, framing: {Nerves.UART.Framing.Line, separator: "\n"})

    {:ok, %{serial_dev: serial_dev}}
  end


  # Handle version call
  def handle_call({:version}, _from, state) do
    {:reply, _send_message(0, 255, :internal, false, I_VERSION), state}
  end


  # Handle discover call
  def handle_call({:discover}, _from, state) do
    {:reply, _send_discover_request(), state}
  end


  # Handle version call
  def handle_call({:scan}, _from, state) do
    Logger.info "Starting scan of MySensors network..."

    # Register scan discovery handler and start the scan
    MySensors.DiscoveryManager.add_handler(__MODULE__.ScanDiscoveryHandler, [])
    _send_discover_request()

    # Manually request presentation from the gateway
    MySensors.PresentationManager.request_presentation(0)

    {:reply, :ok, state}
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


  # Process a presentation message
  defp _process_message(msg = %{command: :presentation}) do
    Logger.debug "Presentation event #{msg}"
    MySensors.PresentationManager.on_presentation_event(msg)
  end


  # Process a req or set message
  defp _process_message(msg = %{command: cmd}) when cmd in [:set, :req] do
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


  # Send a discover request to the network
  defp _send_discover_request do
    Logger.info "Sending discover request"
    _send_message(255, 255, :internal, false, I_DISCOVER_REQUEST)
  end


  defmodule ScanDiscoveryHandler do

    @moduledoc """
    An handler requesting presentation upon discovery
    """

    use GenServer, restart: :temporary

    @timeout 5000

    @doc """
    Start the server
    """
    def start_link(_opts) do
      GenServer.start_link(__MODULE__, [])
    end


    # Init the server
    def init(_) do
      {:ok, %{}, @timeout}
    end


    # Handle discover response
    def handle_cast(msg = %{type: I_DISCOVER_RESPONSE}, state) do
      Logger.info "Node #{msg.node_id} discovered"
      MySensors.PresentationManager.request_presentation(msg.node_id)
      {:noreply, state, @timeout}
    end


    # Fallback
    def handle_cast(_, state) do
      {:noreply, state, @timeout}
    end


    # Timeout to stop the server
    def handle_info(:timeout, state) do
      Logger.info "Network scan finished"
      {:stop, :shutdown, state}
    end

  end

end

