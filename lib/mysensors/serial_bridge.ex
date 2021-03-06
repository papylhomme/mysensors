defmodule MySensors.SerialBridge do
  alias MySensors.TransportBus
  alias MySensors.Message

  @moduledoc """
  A server handling communication with a [MySensors Serial Gateway](https://www.mysensors.org/build/serial_gateway)

  In case the serial device is not present when starting, the server checks
  regularly to reconnect if possible. It also handles gracefuly disconnection
  and reconnect when the device is back.


  # Configuration

  The serial bridge needs a device name and a transmission speed.

      %{
        device: "ttyUSB0",
        speed: 115200
      }

  You can use `enumerate_uarts/0` to obtain a list of available devices on the system.
  """

  use GenServer, start: {__MODULE__, :start_link, [:uuid, :config]}
  require Logger

  # retry timeout for UART connection
  @retry_timeout 5000

  #########
  #  API
  #########

  @doc "Start the server"
  @spec start_link(String.t(), map) :: GenServer.on_start()
  def start_link(network_uuid, config), do: GenServer.start_link(__MODULE__, {network_uuid, config}, name: __MODULE__)


  @doc "Retrieve the UUID used by for the transport topic"
  @spec transport_uuid(String.t(), map, pid) :: String.t()
  def transport_uuid(network_uuid, _config, _server), do: network_uuid


  @doc "Enumerate the UARTs available on the system"
  @spec enumerate_uarts() :: map()
  def enumerate_uarts(), do: Circuits.UART.enumerate


  #############################
  #  GenServer implementation
  #############################

  # Initialize the serial connection at server startup
  @doc false
  def init({network_uuid, config}) do
    device = config.device
    speed = config.speed
    Logger.info("Starting serial bridge on #{device} for network #{network_uuid}")

    # Init UART system
    {:ok, uart} = Circuits.UART.start_link

    # Subscribe to transport
    TransportBus.subscribe_outgoing(network_uuid)

    # Init state and try to connect
    initial_state = %{uart: uart, device: device, speed: speed, network_uuid: network_uuid, status: :disconnected}
    case _try_connect(initial_state) do
      :ok -> {:ok, %{initial_state | status: :connected}}
      _ -> {:ok, %{initial_state | status: :disconnected}, @retry_timeout}
    end
  end

  # Handle timeout to reconnect the UART
  def handle_info(:timeout, state = %{status: :disconnected}) do
    case _try_connect(state) do
      :ok -> {:noreply, %{state | status: :connected}}
      _ -> {:noreply, state, @retry_timeout}
    end
  end

  # Handle UART closed message
  def handle_info({:circuits_uart, _, {:error, :eio}}, state) do
    Logger.warn("UART closed !")
    {:noreply, %{state | status: :disconnected}, @retry_timeout}
  end

  # Handle incoming messages
  def handle_info(msg = {:circuits_uart, _, _}, state = %{device: device}) do
    case msg do
      # error
      {:circuits_uart, ^device, {:error, e}} ->
        Logger.error("UART error: #{inspect(e)}")

      # message received
      {:circuits_uart, ^device, str} ->
        case Message.parse(str) do
          {:error, _, _, _} -> Logger.error("Unrecognized MySensors message: #{str}")
          msg -> TransportBus.broadcast_incoming(state.network_uuid, msg)
        end

      # unknown message
      _ ->
        Logger.warn("Unknown message: #{inspect(msg)}")
    end

    {:noreply, state}
  end

  # Handle outgoing messages
  def handle_info({:mysensors, :outgoing, message}, state) do
    Circuits.UART.write(state.uart, "#{Message.serialize(message)}\n")
    {:noreply, state}
  end

  # Fallback for unknown messages
  def handle_info(msg, state) do
    Logger.warn("Unknown message: #{inspect(msg)}")
    {:noreply, state}
  end


  ###############
  #  Internals
  ###############

  # Try to connect to the serial gateway
  defp _try_connect(%{uart: uart, device: device, speed: speed}) do
    case Map.has_key?(Circuits.UART.enumerate(), device) do
      false ->
        Logger.debug("Serial device #{device} not present, will retry later")
        :not_present

      true ->
        case Circuits.UART.open(
               uart,
               device,
               speed: speed,
               active: true,
               framing: {Circuits.UART.Framing.Line, separator: "\n"}
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
