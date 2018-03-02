defmodule MySensors.Gateway do
  alias MySensors.Bus
  alias MySensors.TransportBus
  alias MySensors.Types
  alias MySensors.Message

  @moduledoc """
  A server handling communication with a [MySensors Gateway](https://www.mysensors.org/download/serial_api_20)
  """

  use GenServer, start: {__MODULE__, :start_link, []}
  require Logger

  # Default timeout when waiting for a reply from the network
  @ack_timeout 1000

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

  @doc """
  Send a message to the MySensors network
  """
  @spec send_message(Message.t()) :: :ok | {:error, term}
  def send_message(message) do
    Logger.debug(fn -> "Sending message #{message}" end)
    TransportBus.broadcast_outgoing(message)
  end

  @doc """
  Send a message to the MySensors network
  """
  @spec send_message(Types.id(), Types.id(), Types.command(), Types.type(), String.t(), boolean) ::
          :ok
  def send_message(node_id, child_sensor_id, command, type, payload \\ "", ack \\ false) do
    Message.new(node_id, child_sensor_id, command, type, payload, ack)
    |> send_message
  end

  @doc """
  Send a message to the MySensors network, waiting for an ack from the destination
  """
  @spec sync_message(Message.t(), timeout) :: :ok | :timeout
  def sync_message(message, timeout \\ @ack_timeout) do
    task =
      Task.async(fn ->
        Bus.subscribe("message_acks")

        message = %{message | ack: true}
        :ok = send_message(message)

        receive do
          {"message_acks", ^message} -> message
        end
      end)

    case Task.yield(task, timeout) || Task.shutdown(task) do
      {:ok, _result} ->
        :ok

      nil ->
        :timeout
    end
  end

  @doc """
  Send a message to the MySensors network, waiting for an ack from the destination
  """
  @spec sync_message(Types.id(), Types.id(), Types.command(), Types.type(), String.t(), timeout) ::
          :ok | :timeout
  def sync_message(
        node_id,
        child_sensor_id,
        command,
        type,
        payload \\ "",
        timeout \\ @ack_timeout
      ) do
    Message.new(node_id, child_sensor_id, command, type, payload, true)
    |> sync_message(timeout)
  end

  @doc """
  Request gateway version
  """
  @spec version() :: :ok
  def version do
    task =
      Task.async(fn ->
        Bus.subscribe("internal")
        :ok = send_message(0, 255, :internal, I_VERSION)

        receive do
          {"internal", %{child_sensor_id: 255, command: :internal, node_id: 0, type: I_VERSION, payload: version}} -> version
        end
      end)

    case Task.yield(task, @ack_timeout) || Task.shutdown(task) do
      {:ok, result} ->
        {:ok, result}

      nil ->
        {:error, :timeout}
    end
  end

  #########################
  # Server implementation #
  #########################

  # Init
  def init(nil) do
    Bus.subscribe("internal")
    TransportBus.subscribe_incoming()

    {:ok, %{}}
  end

  # Handle incoming acks
  def handle_info({:mysensors_incoming, message = %{ack: true}}, state) do
    #Logger.debug "Forwarding ack: #{message}"
    Bus.broadcast("message_acks", message)
    {:noreply, state}
  end

  # Forward incoming internal messages
  def handle_info({:mysensors_incoming, message = %{command: :internal}}, state) do
    #Logger.debug "Forwarding internal command: #{message}"
    Bus.broadcast("internal", message)
    {:noreply, state}
  end

  # Forward incoming presentation messages
  def handle_info({:mysensors_incoming, message = %{command: :presentation}}, state) do
    #Logger.debug "Forwarding presentation: #{message}"
    Bus.broadcast("presentation", message)
    {:noreply, state}
  end

  # Forward requests to nodes
  def handle_info({:mysensors_incoming, message = %{node_id: node_id, command: c}}, state) when c in [:req, :set] do
    #Logger.debug "Forwarding node event: #{message}"
    Bus.broadcast("node_#{node_id}", message)
    {:noreply, state}
  end


  # Forward log messages
  def handle_info({"internal", %{command: :internal, type: I_LOG_MESSAGE, payload: log}}, state) do
    Logger.debug("Received log message: #{log}")
    Bus.broadcast("gwlog", log)
    {:noreply, state}
  end


  # Handle time requests
  def handle_info({"internal", msg = %{command: :internal, type: I_TIME}}, state) do
    Logger.debug("Received time request: #{msg}")

    send_message(
      msg.node_id,
      msg.child_sensor_id,
      :internal,
      I_TIME,
      DateTime.utc_now() |> DateTime.to_unix(:seconds)
    )

    {:noreply, state}
  end

  # Handle config requests
  def handle_info({"internal", msg = %{command: :internal, type: I_CONFIG}}, state) do
    Logger.debug("Received configuration request: #{msg}")

    payload =
      case Application.get_env(:mysensors, :measure) do
        :metric -> "M"
        :imperial -> "I"
        _ -> ""
      end

    send_message(msg.node_id, msg.child_sensor_id, :internal, I_CONFIG, payload)
    {:noreply, state}
  end


  # Forward remaining internal commands to related node
  def handle_info({"internal", msg = %{command: :internal, node_id: node_id}}, state) do
    Bus.broadcast("node_#{node_id}", msg)
    {:noreply, state}
  end

  # Fallback for unknown messages
  def handle_info(msg, state) do
    Logger.warn("Unknown message: #{inspect(msg)}")
    {:noreply, state}
  end

end
