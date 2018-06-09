defmodule MySensors.SerialBridge do
  alias MySensors.TransportBus
  alias MySensors.Message

  @moduledoc """
  A server handling communication with a [MySensors Serial Gateway](https://www.mysensors.org/build/serial_gateway)

  In case the serial device is not present when starting, the server checks
  regularly to reconnect if possible. It also handles gracefuly disconnection
  and reconnect when the device is back.


  # Configuration

  Use `:serial_bridge` to configure the bridge. You can use `Nerves.UART.enumerate/0` to obtain a list of available devices.

      config :mysensors,
        serial_bridge: %{
          device: "ttyUSB0",
          speed: 115200
        }
  """

  use GenServer, start: {__MODULE__, :start_link, [:uuid, :config]}
  require Logger

  # retry timeout for UART connection
  @retry_timeout 5000

  #########
  #  API
  #########

  @doc """
  Start the server
  """
  @spec start_link(String.t(), map) :: GenServer.on_start()
  def start_link(network_uuid, config) do
    GenServer.start_link(__MODULE__, {network_uuid, config}, name: __MODULE__)
  end

  ###############
  #  Internals
  ###############

  # Initialize the serial connection at server startup
  def init({network_uuid, config}) do
    device = config.device
    speed = config.speed

    Logger.info("Starting serial bridge on #{device}")
    TransportBus.subscribe_outgoing(network_uuid)

    initial_state = %{device: device, speed: speed, network_uuid: network_uuid}

    case _try_connect(device, speed) do
      :ok -> {:ok, %{initial_state | status: :connected}}
      _ -> {:ok, %{initial_state | status: :disconnected}, @retry_timeout}
    end
  end

  # Handle timeout to reconnect the UART
  def handle_info(:timeout, state = %{status: :disconnected, device: device, speed: speed}) do
    case _try_connect(device, speed) do
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
  def handle_info(msg = {:nerves_uart, _, _}, state = %{device: device}) do
    case msg do
      # error
      {:nerves_uart, ^device, {:error, e}} ->
        Logger.error("UART error: #{inspect(e)}")

      # message received
      {:nerves_uart, ^device, str} ->
        str
        |> Message.parse()
        |> TransportBus.broadcast_incoming(state.network_uuid)

      # unknown message
      _ ->
        Logger.warn("Unknown message: #{inspect(msg)}")
    end

    {:noreply, state}
  end

  # Handle outgoing messages
  def handle_info({:mysensors, :outgoing, message}, state) do
    Nerves.UART.write(Nerves.UART, "#{Message.serialize(message)}\n")
    {:noreply, state}
  end

  # Fallback for unknown messages
  def handle_info(msg, state) do
    Logger.warn("Unknown message: #{inspect(msg)}")
    {:noreply, state}
  end

  # Try to connect to the serial gateway
  defp _try_connect(device, speed) do
    case Map.has_key?(Nerves.UART.enumerate(), device) do
      false ->
        Logger.debug("Serial device #{device} not present, will retry later")
        :not_present

      true ->
        case Nerves.UART.open(
               Nerves.UART,
               device,
               speed: speed,
               active: true,
               framing: {Nerves.UART.Framing.Line, separator: "\n"}
             ) do
          :ok ->
            Logger.info("Connected to serial device #{device}")
            :ok

          {:error, reason} ->
            Logger.error("Error connecting to serial device #{device}: #{inspect(reason)}")
            :error
        end
    end
  end
end
