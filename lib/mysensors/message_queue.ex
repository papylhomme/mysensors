defmodule MySensors.MessageQueue do
  alias MySensors.Message
  alias __MODULE__.Item

  @moduledoc """
  A queue for MySensors messages
  """

  # TODO max retry count

  use GenServer
  require Logger

  #########
  #  API
  #########

  @doc """
  Start a new message queue
  """
  @spec start_link(fun | nil) :: GenServer.on_start()
  def start_link(network_uuid, handler \\ nil) do
    GenServer.start_link(__MODULE__, {network_uuid, handler})
  end

  @doc """
  Push a message to the queue
  """
  @spec push(pid, Message.t()) :: :ok
  def push(pid, message) do
    GenServer.cast(pid, {:push, message})
  end

  @doc """
  Push a message to the queue
  """
  @spec push(pid, Types.id(), Types.id(), Types.command(), Types.type(), String.t()) :: :ok
  def push(pid, node_id, child_sensor_id, command, type, payload \\ "") do
    msg = Message.new(node_id, child_sensor_id, command, type, payload, true)
    push(pid, msg)
  end

  @doc """
  Queue a message
  """
  @spec queue(pid, Message.t()) :: :ok
  def queue(pid, message) do
    GenServer.cast(pid, {:queue, message})
  end

  @doc """
  Queue a message
  """
  @spec queue(pid, Types.id(), Types.id(), Types.command(), Types.type(), String.t()) :: :ok
  def queue(pid, node_id, child_sensor_id, command, type, payload \\ "") do
    msg = Message.new(node_id, child_sensor_id, command, type, payload, true)
    queue(pid, msg)
  end

  @doc """
  Returns a list of pending messages
  """
  @spec list(pid) :: [Message.t()]
  def list(pid) do
    GenServer.call(pid, {:list})
  end

  @doc """
  Flush the queue
  """
  @spec flush(pid, fun) :: :ok
  def flush(pid, filter \\ fn _msg -> true end) do
    GenServer.cast(pid, {:flush, filter})
  end

  @doc """
  Clear the queue
  """
  @spec clear(pid, fun) :: :ok
  def clear(pid, filter \\ fn _msg -> true end) do
    GenServer.cast(pid, {:clear, filter})
  end

  ###############
  #  Internals
  ###############

  # Initialize the queue
  def init({network_uuid, handler}) do
    {:ok, %{network_uuid: network_uuid, handler: handler, message_queue: []}}
  end

  # Handle list call
  def handle_call({:list}, _from, state) do
    {:reply, state.message_queue, state}
  end

  # Handle push cast
  def handle_cast({:push, message}, state) do
    _async_send(state, Item.new(state.network_uuid, message))
    {:noreply, state}
  end

  # Handle queue cast
  def handle_cast({:queue, message}, state) do
    {:noreply, _enqueue_message(state, Item.new(state.network_uuid, message))}
  end

  # Handle clear cast
  def handle_cast({:clear, filter}, state) do
    message_queue =
      state.message_queue
      |> Enum.reject(fn item -> filter.(item) end)

    _on_event(state, {:cleared})

    {:noreply, %{state | message_queue: message_queue}}
  end

  # Handle flush cast
  def handle_cast({:flush, filter}, state) do
    message_queue =
      state.message_queue
      |> Enum.filter(fn item ->
        case filter.(item) do
          true ->
            _async_send(state, item)
            false

          false ->
            true
        end
      end)

    {:noreply, %{state | message_queue: message_queue}}
  end

  # Handle message sender's shutdown
  def handle_info({:DOWN, _, _, _, {:shutdown, reason}}, state) do
    case reason do
      {:timeout, item} -> {:noreply, _enqueue_message(state, item)}
      {:ok, item} ->
        _on_event(state, {:message_sent, item})
        {:noreply, state}
    end
  end

  # Enqueue a message
  # prevent multiple :set messages for the same sensor
  defp _enqueue_message(state, item = %{message: %{command: :set}}) do
    m = Map.delete(item.message, :payload)

    case Enum.find_index(state.message_queue, fn i ->
           i.message |> Map.delete(:payload) |> Map.equal?(m)
         end) do
      nil ->
        _on_event(state, {:message_queued, item})
        %{state | message_queue: state.message_queue ++ [item]}

      idx ->
        %{state | message_queue: List.delete_at(state.message_queue, idx) ++ [item]}
    end
  end

  # Enqueue a message
  # don't enqueue if an equivalent message is already waiting
  defp _enqueue_message(state, item = %{message: msg}) do
    case Enum.find(state.message_queue, fn %{message: m} -> match?(^msg, m) end) do
      nil ->
        _on_event(state, {:message_queued, item})
        %{state | message_queue: state.message_queue ++ [item]}
      _ -> state
    end
  end

  # Try to send a message
  defp _async_send(state, item) do
    item
    |> Item.send
    |> Process.monitor

    _on_event(state, {:sending_message, item})
  end

  # Notify handler with event
  defp _on_event(state, event) do
    unless is_nil(state.handler) do
      state.handler.(event)
    end
  end

  # Simple server sending a message and waiting for the ack
  defmodule Item do
    @moduledoc false
    use GenServer

    defstruct id: nil, network_uuid: nil, retry: 0, timestamp: nil, last_retry: nil, message: nil

    # Create a new item struct from the given message
    def new(network_uuid, message) do
      %__MODULE__{id: :erlang.unique_integer, network_uuid: network_uuid, timestamp: DateTime.utc_now, message: message}
    end

    # Create a new queue item and try to send the given message
    def send(item) do
      {:ok, pid} = GenServer.start(__MODULE__, %__MODULE__{item | retry: item.retry + 1, last_retry: DateTime.utc_now})
      pid
    end

    # Start the server and immediately timeout to send the message
    def init(item) do
      {:ok, item, 0}
    end

    # Handle timeout to send the message
    def handle_info(:timeout, state) do
      status =
        state.network_uuid
        |> MySensors.by_uuid
        |> MySensors.Network.sync_message(state.message)

      {:stop, {:shutdown, {status, state}}, state}
    end
  end
end
