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
  Initialize the serial connection at server startup
  """
  def init(serial_dev) do
    Logger.debug "Starting MySensors serial gateway on #{serial_dev}"
    :ok = Nerves.UART.open(Nerves.UART, serial_dev, speed: 115200, active: true, framing: {Nerves.UART.Framing.Line, separator: "\n"})

    {:ok, %{serial_dev: serial_dev}}
  end


  @doc """
  Send a message to the gateway
  """
  def handle_call({:send, message}, _from, state) do
    Logger.debug fn -> "Sending message #{MySensors.Message.parse(message)}" end

    :ok = Nerves.UART.write(Nerves.UART, message)
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
      _             -> Logger.debug "Internal event #{msg}"
    end
  end


  # Process an error message
  defp _process_message({:error, e, stacktrace}) do
    Logger.error "Error processing input #{inspect e}\n#{stacktrace |> Exception.format_stacktrace}"
  end


  # Process an unknown message
  defp _process_message(msg) do
    Logger.warn "Unknown event #{inspect msg}"
  end

end

