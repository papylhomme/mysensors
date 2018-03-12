defmodule MySensors.Bus do
  alias Phoenix.PubSub
  alias MySensors.Types
  alias MySensors.Message

  @moduledoc """
  PubSub implementation for bridge communication
  """

  @bridge_name Application.get_env(:mysensors, :bus_name, __MODULE__)

  @topic_log "gwlog"
  @topic_nodes_events "nodes_events"
  @topic_sensors_events "sensors_events"

  @doc """
  Subscribe the caller to the log topic

  Subscribers will receive log as `{:mysensors, :log, message}` tuples.
  """
  @spec subscribe_log() :: :ok | {:error, term}
  def subscribe_log() do
    PubSub.subscribe(@bridge_name, @topic_log)
  end

  @doc """
  Broadcast a log message
  """
  @spec broadcast_log(Message.t()) :: :ok | {:error, term}
  def broadcast_log(message) do
    PubSub.broadcast(@bridge_name, @topic_log, {:mysensors, :log, message})
  end

  @doc """
  Subscribe the caller to the `node`'s topic

  Subscribers will receive node messages as `{:mysensors, :message, message}` tuples.
  """
  @spec subscribe_node(Types.id()) :: :ok | {:error, term}
  def subscribe_node(node_id) do
    PubSub.subscribe(@bridge_name, _node_topic(node_id))
  end

  @doc """
  Broadcast a node message
  """
  @spec broadcast_node_message(Message.t()) :: :ok | {:error, term}
  def broadcast_node_message(message = %{node_id: node_id}) do
    PubSub.broadcast(@bridge_name, _node_topic(node_id), {:mysensors, :message, message})
  end

  @doc """
  Subscribe the caller to the sensors events topic

  Subscribers will receive node messages as `{:mysensors, :sensor_event, event}` tuples.
  """
  @spec subscribe_sensors_events() :: :ok | {:error, term}
  def subscribe_sensors_events() do
    PubSub.subscribe(@bridge_name, @topic_sensors_events)
  end

  @doc """
  Broadcast a sensor event
  """
  @spec broadcast_sensor_event(any) :: :ok | {:error, term}
  def broadcast_sensor_event(event) do
    PubSub.broadcast(@bridge_name, @topic_sensors_events, {:mysensors, :sensor_event, event})
  end

  @doc """
  Subscribe the caller to the nodes events topic

  Subscribers will receive node events as `{:mysensors, :node_event, event}` tuples.
  """
  @spec subscribe_nodes_events() :: :ok | {:error, term}
  def subscribe_nodes_events() do
    PubSub.subscribe(@bridge_name, @topic_nodes_events)
  end

  @doc """
  Broadcast a node event
  """
  @spec broadcast_node_event(any) :: :ok | {:error, term}
  def broadcast_node_event(event) do
    PubSub.broadcast(@bridge_name, @topic_nodes_events, {:mysensors, :node_event, event})
  end

  @doc """
  Defines the specification for a supervisor
  """
  def child_spec(_args) do
    Supervisor.child_spec(
      %{start: {PubSub.PG2, :start_link, [@bridge_name, []]}, id: @bridge_name},
      []
    )
  end

  # Helper to generate a topic string from a node id
  defp _node_topic(node_id) do
    "node_#{node_id}"
  end
end
