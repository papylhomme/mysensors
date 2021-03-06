defmodule MySensors.Network do
  alias MySensors.TransportBus
  alias MySensors.Types
  alias MySensors.Message
  alias MySensors.Node
  alias MySensors.MessageQueue
  alias MySensors.PresentationAccumulator

  @moduledoc """
  A server to interract with a MySensors network
  """
  use GenServer, start: {__MODULE__, :start_link, [:uuid, :config]}
  require MySensors.PubSub

  require Logger


  # Default timeout when waiting for a reply from the network
  @ack_timeout 1000

  defstruct name: nil,
      uuid: nil,
      supervisor: nil,
      table: nil,
      presentations: %{},
      queue: nil,
      transport_uuid: nil


  @typedoc "Network configuration"
  @type config :: %{name: atom, transport: term()}


  @typedoc "Status of a network"
  @type status :: :stopped | {:running, t} | {:error, term()}


  @typedoc "Network information"
  @type t :: %__MODULE__{
    name: String.t(),
    uuid: MySensors.uuid(),
    supervisor: pid(),
    table: reference(),
    presentations: map(),
    queue: pid(),
    transport_uuid: MySensors.uuid()
  }



  #########
  #  API
  #########

  @doc "Start the server"
  @spec start_link(MySensors.uuid, Network.config) :: GenServer.on_start()
  def start_link(uuid, config),  do: GenServer.start_link(__MODULE__, {uuid, config}, name: MySensors.by_uuid(uuid))


  @doc "Retrieve information about the network"
  @spec info(pid) :: Node.t()
  def info(server), do: GenServer.call(server, :info)

  @doc "List the known nodes"
  @spec nodes(pid) :: [Node.t()]
  def nodes(server), do: GenServer.call(server, :list_nodes)

  @doc "Send a discover command and request presentation from discovered nodes"
  @spec scan(pid) :: :ok
  def scan(server), do: GenServer.cast(server, :scan)

  @doc "Request presentation from a node"
  @spec request_presentation(pid, Types.id()) :: :ok
  def request_presentation(server, node), do: :ok = GenServer.cast(server, {:request_presentation, node})

  @doc "Send a message to the MySensors network"
  @spec send_message(pid, Message.t()) :: :ok | {:error, term}
  def send_message(server, message), do: :ok = GenServer.call(server, {:send_message, message})

  @doc "Send a message to the MySensors network, waiting for an ack from the destination"
  @spec sync_message(pid, Message.t(), timeout) :: :ok | :timeout
  def sync_message(server, message, timeout \\ @ack_timeout) do
    node_uuid = GenServer.call(server, {:node_uuid, message.node_id})
    task =
      Task.async(fn ->
        Node.subscribe_nodes_messages(node_uuid)

        message = %{message | ack: true}
        :ok = send_message(server, message)

        receive do
          {:mysensors, :nodes_messages, ^message} -> message
        end
      end)

    case Task.yield(task, timeout) || Task.shutdown(task) do
      {:ok, _result} ->
        :ok
      nil ->
        :timeout
    end
  end


  @doc "Request gateway version"
  @spec request_version(pid) :: {:ok, String.t} | {:error, :timeout}
  def request_version(server) do
    info = GenServer.call(server, :info)
    task =
      Task.async(fn ->
        TransportBus.subscribe_incoming(info.transport_uuid)
        :ok = send_message(server, Message.new(0, 255, :internal, I_VERSION))

        receive do
          {:mysensors, :incoming,
           %{
             child_sensor_id: 255,
             command: :internal,
             node_id: 0,
             type: I_VERSION,
             payload: version
           }} ->
            version
        end
      end)

    case Task.yield(task, @ack_timeout) || Task.shutdown(task) do
      {:ok, result} ->
        {:ok, result}
      nil ->
        {:error, :timeout}
    end
  end


  ############
  #  Events
  ############

  MySensors.PubSub.topic_helpers(MySensors.Bus, :gwlogs, fn network_uuid -> "network_#{network_uuid}_gwlogs" end)


  ####################
  #  Implementation
  ####################

  # Initialize the server
  def init({uuid, config}) do
    # Open database
    nodes_db =
      Application.get_env(:mysensors, :data_dir, "./")
      |> Path.join("network_#{uuid}.db")
      |> String.to_charlist

    {:ok, tid} = :dets.open_file(nodes_db, ram_file: true, auto_save: 10)

    # Start direct children
    {:ok, queue} = MessageQueue.start_link(uuid)
    {:ok, supervisor} = Supervisor.start_link([], strategy: :one_for_one)


    # Init transport and state
    initial_state = %__MODULE__{
      name: config.name,
      uuid: uuid,
      supervisor: supervisor,
      table: tid,
      presentations: %{},
      queue: queue,
      transport_uuid: nil
    }

    state =
      case config.transport do
        {module, transport_config} ->
          {:ok, pid} = apply(module, :start_link, [uuid, transport_config])
          transport_uuid = apply(module, :transport_uuid, [uuid, transport_config, pid])
          %{initial_state | transport_uuid: transport_uuid}
        _ -> raise "Unknown transport config: #{inspect config.transport}"
      end

    # Init nodes
    Logger.info("Initializing nodes from storage...")
    :dets.traverse(state.table, fn {node_uuid, _node_specs} ->
      _start_child(state, node_uuid)
      :continue
    end)

    # Subscribe to transport
    TransportBus.subscribe_incoming(state.transport_uuid)

    {:ok, state}
  end

  # Handle scan cast
  def handle_cast(:scan, state) do
    Logger.info("Sending discover request")
    _send_message(state, Message.new(255, 255, :internal, I_DISCOVER_REQUEST))

    # manually request presentation from gateway
    {:noreply, %{state | presentations: _request_presentation(state, 0)}}
  end

  # Handle request presentation cast
  def handle_cast({:request_presentation, node_id}, state) do
    {:noreply, %{state | presentations: _request_presentation(state, node_id)}}
  end


  # Handle info call
  def handle_call(:info, _from, state) do
    {:reply, state, state}
  end


  # Handle list_nodes call
  # TODO use db to list nodes, and report crashed ones (when its server is no longer running)
  def handle_call(:list_nodes, _from, state) do
    res =
      Supervisor.which_children(state.supervisor)
      |> Enum.map(fn {_id, pid, _, _} -> Node.info(pid) end)

    {:reply, res, state}
  end


  # Send a message to the network
  def handle_call({:send_message, message}, _from, state) do
    _send_message(state, message)
    {:reply, :ok, state}
  end


  def handle_call({:node_uuid, node_id}, _from, state) do
    {:reply, _node_uuid(state.uuid, node_id), state}
  end


  #####################
  #  Message handlers
  #####################


  # Forward requests to nodes
  def handle_info({:mysensors, :incoming, message = %{command: c}}, state) when c in [:req, :set] do
    Node.broadcast_nodes_messages(_node_uuid(state.uuid, message.node_id), message)
    {:noreply, state}
  end

  # Discard unused gateway commands
  def handle_info({:mysensors, :incoming, %{command: :internal, type: type}}, state)
      when type in [I_VERSION] do
    {:noreply, state}
  end

  # Forward log messages
  # TODO keep it that way, use a log channel per network, only log to console ?
  def handle_info(
        {:mysensors, :incoming, %{command: :internal, type: I_LOG_MESSAGE, payload: log}},
        state
      ) do
    broadcast_gwlogs(state.uuid, log)
    {:noreply, state}
  end

  # Handle time requests
  def handle_info({:mysensors, :incoming, msg = %{command: :internal, type: I_TIME}}, state) do
    Logger.debug("Received time request: #{msg}")

    _send_message(state, Message.new(
      msg.node_id,
      msg.child_sensor_id,
      :internal,
      I_TIME,
      DateTime.utc_now() |> DateTime.to_unix(:seconds)
    ))

    {:noreply, state}
  end

  # Handle config requests
  def handle_info({:mysensors, :incoming, msg = %{command: :internal, type: I_CONFIG}}, state) do
    Logger.debug("Received configuration request: #{msg}")

    payload =
      case Application.get_env(:mysensors, :measure) do
        :metric -> "M"
        :imperial -> "I"
        _ -> ""
      end

    _send_message(state, Message.new(
      msg.node_id,
      msg.child_sensor_id,
      :internal,
      I_CONFIG,
      payload
    ))
    {:noreply, state}
  end


  # Handle presentation initiated by node
  def handle_info(
        {:mysensors, :incoming,
         msg = %{command: :presentation, child_sensor_id: 255, node_id: node_id}},
        state
      ) do
    presentations =
      case Map.get(state.presentations, node_id) do
        nil ->
          Logger.info("Receiving presentation from node #{node_id}...")
          p = _init_accumulator(state.presentations, node_id)
          send(p[node_id], msg)
          p

        pid ->
          send(pid, msg)
          state.presentations
      end

    {:noreply, %{state | presentations: presentations}}
  end

  # Forward presentation messages to accumulator
  def handle_info({:mysensors, :incoming, msg = %{command: :presentation, node_id: node_id}}, state) do
    acc = state.presentations[node_id]
    unless is_nil(acc), do: send(acc, msg)
    {:noreply, state}
  end

  # Forward sketch info messages to accumulator
  def handle_info(
        {:mysensors, :incoming,
         msg = %{node_id: node_id, child_sensor_id: 255, command: :internal, type: t}},
        state
      )
      when t in [I_SKETCH_NAME, I_SKETCH_VERSION] do
    acc = state.presentations[node_id]
    unless is_nil(acc), do: send(acc, msg)
    {:noreply, state}
  end

  # Handle internal commands
  def handle_info(
        {:mysensors, :incoming,
         msg = %{
           command: :internal,
           child_sensor_id: 255,
           node_id: node_id
         }},
        state
      ) do

    # Handle node awakening to flush related presentation requests
    if msg.type == I_POST_SLEEP_NOTIFICATION do
      MessageQueue.flush(state.queue, fn i -> i.message.node_id == node_id end)
    end

    # Request presentation if node is unknown
    uuid = _node_uuid(state.uuid, node_id)
    case _node_known?(state, uuid) do
      false -> {:noreply, %{state | presentations: _request_presentation(state, node_id)}}
      true ->
        Node.broadcast_nodes_messages(uuid, msg)
        {:noreply, state}
    end
  end

  # Discard remaining MySensors messages
  def handle_info({:mysensors, :incoming, _message}, state) do
    {:noreply, state}
  end

  # Handle accumulator finishing
  def handle_info({:DOWN, _, _, _, {:shutdown, acc}}, state) do
    case _accumulator_ready?(acc) do
      false ->
        Logger.debug("Discarding empty accumulator for node #{acc.node_id} #{inspect(acc)}")

      true ->
        Logger.debug("Presentation accumulator for node #{acc.node_id} finishing #{inspect(acc)}")
        _node_presentation(state, %{acc | last_seen: DateTime.utc_now()})
    end

    {:noreply, %{state | presentations: Map.delete(state.presentations, acc.node_id)}}
  end



  ##############
  #  Internals
  ##############

  # Generate an UUID for the given node
  defp _node_uuid(network_uuid, node_id) do
    UUID.uuid5(network_uuid, "#{node_id}")
  end

  # Start a supervised node server
  defp _start_child(state, node_uuid) do
    child_spec = Supervisor.child_spec({Node, {state.uuid, state.table, node_uuid}}, id: node_uuid)
    {:ok, _pid} = Supervisor.start_child(state.supervisor, child_spec)
  end

  # Initialize a presentation accumulator for the given node
  defp _init_accumulator(presentations, node, type \\ nil, version \\ nil) do
    {:ok, pid} = PresentationAccumulator.start_link(node, type, version)
    Process.monitor(pid)
    Map.put(presentations, node, pid)
  end

  # Test if an accumulator has received sufficient information
  defp _accumulator_ready?(acc) do
    not (is_nil(acc.node_id) or is_nil(acc.type) or map_size(acc.sensors) == 0)
  end

  # Test whether is known in the system or not
  defp _node_known?(state, node_uuid) do
    :dets.lookup(state.table, node_uuid) != []
  end

  # Send a message to the network
  defp _send_message(state, message) do
    Logger.debug(fn -> "Sending message #{message}" end)
    TransportBus.broadcast_outgoing(state.transport_uuid, message)
  end

  # Request presentation for the given node
  defp _request_presentation(state, node_id) do
    case Map.has_key?(state.presentations, node_id) do
      true -> state.presentations
      false ->
        Logger.info("Requesting presentation from node #{node_id}...")
        MessageQueue.push(state.queue, Message.new(node_id, 255, :internal, I_PRESENTATION))
        state.presentations |> _init_accumulator(node_id)
      end
  end

  # Handle presentation from a node
  defp _node_presentation(state, acc = %{node_id: node_id}) do
    uuid = _node_uuid(state.uuid, node_id)

    case _node_known?(state, uuid) do
      false ->
        Logger.info("New node registration #{inspect(acc)}")
        :ok = :dets.insert(state.table, {uuid, acc})
        {:ok, pid} = _start_child(state, uuid)

        Node.NodeDiscoveredEvent.broadcast(Node.info(pid))

      true ->
        :ok = :dets.insert(state.table, {uuid, acc})

        child =
          Supervisor.which_children(state.supervisor)
          |> Enum.find(fn {local_uuid, _, _, _} -> local_uuid == uuid end)

        case child do
          {_, pid, _, _} -> Node.update_specs(pid, %{acc | uuid: uuid})
          _ -> nil
        end
    end
  end

end
