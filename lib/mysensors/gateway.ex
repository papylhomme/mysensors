defmodule MySensors.Gateway do
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
  @spec send_message(Message.t()) :: :ok
  def send_message(message) do
    GenServer.cast(__MODULE__, {:send_message, message})
  end

  @doc """
  Send a message to the MySensors network
  """
  @spec send_message(Types.id(), Types.id(), Types.command(), Types.type(), String.t(), boolean) ::
          :ok
  def send_message(node_id, child_sensor_id, command, type, payload \\ "", ack \\ false) do
    MySensors.Message.new(node_id, child_sensor_id, command, type, payload, ack)
    |> send_message
  end

  @doc """
  Send a message to the MySensors network, waiting for an ack from the destination
  """
  @spec sync_message(Message.t(), timeout) :: :ok | :timeout
  def sync_message(message, timeout \\ @ack_timeout) do
    task =
      Task.async(fn ->
        :ok = GenServer.call(__MODULE__, {:sync_message, message})

        receive do
          v -> v
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
    MySensors.Message.new(node_id, child_sensor_id, command, type, payload, true)
    |> sync_message(timeout)
  end

  @doc """
  Request gateway version
  """
  @spec version() :: :ok
  def version do
    task =
      Task.async(fn ->
        :ok = GenServer.call(__MODULE__, {:version})

        receive do
          v -> v
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
    Phoenix.PubSub.subscribe(MySensors.PubSub, "incoming")
    {:ok, %{version_handlers: [], ack_handlers: []}}
  end

  # Handle version call
  def handle_call({:version}, _from = {pid, _ref}, state) do
    {:reply, _send_message(0, 255, :internal, I_VERSION),
     %{state | version_handlers: state.version_handlers ++ [pid]}}
  end

  # Handle sync_message call
  def handle_call({:sync_message, message}, _from = {pid, _ref}, state) do
    _send_message(%{message | ack: true})
    {:reply, :ok, %{state | ack_handlers: state.ack_handlers ++ [{message, pid}]}}
  end

  # Handle send_message cast
  def handle_cast({:send_message, message}, state) do
    _send_message(%{message | ack: false})
    {:noreply, state}
  end

  # Handle incoming acks
  def handle_info({:mysensors_incoming, message = %{ack: true}}, state) do
    Logger.debug("Handling ack: #{message}")

    case Enum.find_index(state.ack_handlers, fn {original, _handler} -> message == original end) do
      nil ->
        {:noreply, state}

      i ->
        {{_original, handler}, handlers} = List.pop_at(state.ack_handlers, i)
        if Process.alive?(handler), do: send(handler, message)
        {:noreply, %{state | ack_handlers: handlers}}
    end
  end

  # Handle version response
  def handle_info({:mysensors_incoming, message = %{command: :internal, type: I_VERSION}}, state) do
    Logger.debug("Handling version response: #{message}")

    case state.version_handlers do
      [] ->
        {:noreply, state}

      [handler | handlers] ->
        send(handler, message.payload)
        {:noreply, %{state | version_handlers: handlers}}
    end
  end

  # Handle incoming messages
  def handle_info({:mysensors_incoming, message}, state) do
    _process_message(message)
    {:noreply, state}
  end

  # Fallback for unknown messages
  def handle_info(msg, state) do
    Logger.warn("Unknown message: #{inspect(msg)}")
    {:noreply, state}
  end

  #################
  #   Internals   #
  #################

  # Process a presentation message
  defp _process_message(msg = %{command: :presentation}) do
    Logger.debug("Presentation event #{msg}")
    MySensors.PresentationManager.on_presentation_event(msg)
  end

  # Handle gateway ready
  defp _process_message(%{command: :internal, type: I_GATEWAY_READY}) do
    Logger.info("Gateway ready !")
  end

  # Log from the gateway
  defp _process_message(msg = %{command: :internal, type: I_LOG_MESSAGE}) do
    Phoenix.PubSub.broadcast(MySensors.PubSub, "gwlog", {:mysensors_gwlog, msg.payload})
  end

  # Forward discover responses to the discovery manager
  defp _process_message(msg = %{command: :internal, type: I_DISCOVER_RESPONSE}) do
    Logger.debug("Discover response #{msg}")
    MySensors.DiscoveryManager.notify(msg)
  end

  # Process time requests
  defp _process_message(msg = %{command: :internal, type: I_TIME}) do
    Logger.debug("Requesting controller time #{msg}")

    _send_message(
      msg.node_id,
      msg.child_sensor_id,
      :internal,
      I_TIME,
      DateTime.utc_now() |> DateTime.to_unix(:seconds)
    )
  end

  # Process config requests
  defp _process_message(msg = %{command: :internal, type: I_CONFIG}) do
    Logger.debug("Requesting controller configuration #{msg}")

    payload =
      case Application.get_env(:mysensors, :measure) do
        :metric -> "M"
        :imperial -> "I"
        _ -> ""
      end

    _send_message(msg.node_id, msg.child_sensor_id, :internal, I_CONFIG, payload)
  end

  # Forward sketch information to the presentation manager
  defp _process_message(msg = %{command: :internal, type: t})
       when t in [I_SKETCH_NAME, I_SKETCH_VERSION] do
    Logger.debug("Sketch information event #{msg}")
    MySensors.PresentationManager.on_presentation_event(msg)
  end

  # Forward other message to their related node
  defp _process_message(msg = %{node_id: node_id}) do
    Phoenix.PubSub.broadcast(MySensors.PubSub, "node_#{node_id}", {:mysensors_message, msg})
  end

  # Process an error message
  defp _process_message({:error, input, e, stacktrace}) do
    Logger.error(
      "Error processing input '#{input}': #{inspect(e)}\n#{
        stacktrace |> Exception.format_stacktrace()
      }"
    )
  end

  # Process unexpected messages
  defp _process_message(msg) do
    Logger.debug("Unexpected message: #{inspect(msg)}")
  end

  # Construct and send a message to the gateway
  defp _send_message(node_id, child_sensor_id, command, type, payload \\ "", ack \\ false) do
    MySensors.Message.new(node_id, child_sensor_id, command, type, payload, ack)
    |> _send_message
  end

  # Send a message to the gateway
  defp _send_message(msg) do
    str = MySensors.Message.serialize(msg)

    Logger.debug(fn -> "Sending message #{msg}" end)
    Phoenix.PubSub.broadcast(MySensors.PubSub, "outgoing", {:mysensors_outgoing, str})
  end
end
