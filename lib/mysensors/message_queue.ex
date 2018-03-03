defmodule MySensors.MessageQueue do
  alias MySensors.Message
  alias __MODULE__.Sender

  @moduledoc """
  A queue for MySensors messages
  """

  use GenServer, start: {__MODULE__, :start_link, []}
  require Logger

  #########
  #  API
  #########

  @doc """
  Start a new message queue
  """
  @spec start_link() :: GenServer.on_start()
  def start_link() do
    GenServer.start_link(__MODULE__, nil)
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
  def flush(pid, filter \\ fn msg -> match?(%{}, msg) end) do
    GenServer.cast(pid, {:flush, filter})
  end

  ###############
  #  Internals
  ###############

  # Initialize the queue
  def init(_params) do
    {:ok, %{message_queue: []}}
  end

  # Handle list call
  def handle_call({:list}, _from, state) do
    {:reply, state.message_queue, state}
  end

  # Handle push cast
  def handle_cast({:push, message}, state) do
    _async_send(message)
    {:noreply, state}
  end

  # Handle queue cast
  def handle_cast({:queue, message}, state) do
    {:noreply, _enqueue_message(state, message)}
  end

  # Handle flush cast
  def handle_cast({:flush, filter}, state) do
    message_queue =
      state.message_queue
      |> Enum.filter(fn msg ->
        case filter.(msg) do
          true ->
            _async_send(msg)
            false

          false -> true
        end
      end)

    {:noreply, %{state | message_queue: message_queue}}
  end

  # Handle message sender's shutdown
  def handle_info(msg = {:DOWN, _, _, _, {:shutdown, reason}}, state) do
    case reason do
      {:ok, _} -> {:noreply, state}
      {:timeout, msg} -> {:noreply, _enqueue_message(state, msg)}
    end
  end

  # Enqueue a message
  defp _enqueue_message(state, message) do
    %{state | message_queue: state.message_queue ++ [message]}
  end

  # Try to send a message
  defp _async_send(message) do
    {:ok, pid} = GenServer.start(Sender, message)
    Process.monitor(pid)
  end


  defmodule Sender do
    use GenServer

    def init(message) do
      {:ok, message, 0}
    end

    def handle_info(:timeout, state) do
      {:stop, {:shutdown, {MySensors.Gateway.sync_message(state), state}}, state}
    end
  end

end
