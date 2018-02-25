defmodule MySensors.SerialBridge do
  alias MySensors.TransportBus
  alias MySensors.Message

  @moduledoc """
  A server handling communication with a [MySensors Serial Gateway](https://www.mysensors.org/build/serial_gateway)

  In case the serial device is not present when starting, the server checks
  regularly to reconnect if possible. It also handles gracefuly disconnection
  and reconnect when the device is back.


  # Configuration

  Use `:uart` to set a serial device. You can use `Nerves.UART.enumerate/0` to obtain a list of available devices.

      config :mysensors,
        uart: "ttyUSB0"
  """

  use GenServer, start: {__MODULE__, :start_link, []}
  require Logger

  # retry timeout for UART connection
  @retry_timeout 5000

  #########
  #  API
  #########

  @doc """
  Start the server
  """
  @spec start_link :: GenServer.on_start()
  def start_link do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  ###############
  #  Internals
  ###############

  # Initialize the serial connection at server startup
  def init(nil) do
    serial_dev = Application.get_env(:mysensors, :uart)
    if is_nil(serial_dev), do: raise("Missing configuration key :uart")

    Logger.info("Starting serial bridge on #{serial_dev}")
    TransportBus.subscribe_outgoing()

    case _try_connect(serial_dev) do
      :ok -> {:ok, %{serial_dev: serial_dev, status: :connected}}
      _ -> {:ok, %{serial_dev: serial_dev, status: :disconnected}, @retry_timeout}
    end
  end

  # Handle timeout to reconnect the UART
  def handle_info(:timeout, state = %{status: :disconnected, serial_dev: serial_dev}) do
    case _try_connect(serial_dev) do
      :ok -> {:noreply, %{state | status: :connected}}
      _ -> {:noreply, state, @retry_timeout}
    end
  end

  # Handle UART closed message
  def handle_info({:nerves_uart, _, {:error, :eio}}, state) do
    Logger.warn("UART closed !")
    {:noreply, %{state | status: :disconnected}, @retry_timeout}
  end

  # Handle incoming messages
  def handle_info(msg = {:nerves_uart, _, _}, state = %{serial_dev: serial_dev}) do
    case msg do
      # error
      {:nerves_uart, ^serial_dev, {:error, e}} ->
        Logger.error("UART error: #{inspect(e)}")

      # message received
      {:nerves_uart, ^serial_dev, str} ->
        str
        |> Message.parse()
        |> TransportBus.broadcast_incoming()

      # unknown message
      _ ->
        Logger.warn("Unknown message: #{inspect(msg)}")
    end

    {:noreply, state}
  end

  # Handle outgoing messages
  def handle_info({:mysensors_outgoing, message}, state) do
    Nerves.UART.write(Nerves.UART, "#{Message.serialize(message)}\n")
    {:noreply, state}
  end

  # Fallback for unknown messages
  def handle_info(msg, state) do
    Logger.warn("Unknown message: #{inspect(msg)}")
    {:noreply, state}
  end

  # Try to connect to the serial gateway
  defp _try_connect(serial_dev) do
    case Map.has_key?(Nerves.UART.enumerate(), serial_dev) do
      false ->
        Logger.debug("Serial device #{serial_dev} not present, will retry later")
        :not_present

      true ->
        case Nerves.UART.open(
               Nerves.UART,
               serial_dev,
               speed: 115_200,
               active: true,
               framing: {Nerves.UART.Framing.Line, separator: "\n"}
             ) do
          :ok ->
            Logger.info("Connected to serial device #{serial_dev}")
            :ok

          {:error, reason} ->
            Logger.error("Error connecting to serial device #{serial_dev}: #{inspect(reason)}")
            :error
        end
    end
  end
end
