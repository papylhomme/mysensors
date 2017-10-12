defmodule MySensors.Gateway do

  @moduledoc """
  A server handling communication with MySensors Serial Gateway
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
    :ok = GenServer.call(__MODULE__, {:send, message})
  end


  @doc """
  Request gateway version
  """
  def version do
    :ok = GenServer.call(__MODULE__, {:version})
  end


  @doc """
  Initialize the serial connection at server startup
  """
  def init(serial_dev) do
    Logger.debug "Starting MySensors serial gateway on #{serial_dev}"
    :ok = Nerves.UART.open(Nerves.UART, serial_dev, speed: 115200, active: true, framing: {Nerves.UART.Framing.Line, separator: "\n"})

    {:ok, %{serial_dev: serial_dev}}
  end


  @doc """
  Handle calls to the server
  """

  # Handle version call
  def handle_call({:version}, _from, state) do
    :ok =
      MySensors.Message.new(0, 255, :internal, false, I_VERSION, "")
      |> _send_message

    {:reply, :ok, state}
  end


  # Handle send message call
  def handle_call({:send, message}, _from, state) do
    :ok =
      message
      |> _send_message

    {:reply, :ok, state}
  end


  @doc """
  Handle incoming messages
  """
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
  end


  # Process a set message
  defp _process_message(msg = %{command: :set}) do
    Logger.debug "Set event #{msg}"
  end


  # Process a command message
  defp _process_message(msg = %{command: :req}) do
    Logger.debug "Req event #{msg}"
  end


  # Process an internal message
  defp _process_message(msg = %{command: :internal}) do

    case msg.type do
      I_LOG_MESSAGE -> Logger.debug "GWLOG #{msg.payload}"

      I_TIME        ->
        Logger.debug "Requesting controller time #{msg}"

        MySensors.Message.new(msg.node_id, msg.child_sensor_id, :internal, false, I_TIME, DateTime.utc_now |> DateTime.to_unix(:seconds))
        |> _send_message

      I_CONFIG      ->
        Logger.debug "Requesting controller configuration #{msg}"

        payload =
          case Application.get_env(:mysensors, :measure) do
            :metric   -> "M"
            :imperial -> "I"
            _         -> ""
          end

        MySensors.Message.new(msg.node_id, msg.child_sensor_id, :internal, false, I_CONFIG, payload)
        |> _send_message

      _             -> Logger.debug "Internal event #{msg}"
    end
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

end

