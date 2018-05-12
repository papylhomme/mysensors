defmodule MySensors.Bus do
  alias Phoenix.PubSub
  alias MySensors.Types
  alias MySensors.Message

  use MySensors.PubSub

  @moduledoc """
  PubSub implementation for bridge communication
  """

  @bridge_name Application.get_env(:mysensors, :bus_name, __MODULE__)


  topic_helpers(@bridge_name, :gateway_logs)
  topic_helpers(@bridge_name, :sensors_events)
  topic_helpers(@bridge_name, :nodes_events)
  topic_helpers(@bridge_name, :node_commands, fn node_id -> "node_#{node_id}_commands" end)


  @doc """
  Subscribe the caller to the `node`'s topic

  Subscribers will receive node messages as `{:mysensors, :message, message}` tuples.
  """
  @spec subscribe_node_messages(Types.id()) :: :ok | {:error, term}
  def subscribe_node_messages(node_id) do
    PubSub.subscribe(@bridge_name, _node_topic(node_id))
  end

  @doc """
  Unsubscribe the caller from the `node`'s topic
  """
  @spec unsubscribe_node_messages(Types.id()) :: :ok | {:error, term}
  def unsubscribe_node_messages(node_id) do
    PubSub.unsubscribe(@bridge_name, _node_topic(node_id))
  end


  @doc """
  Broadcast a node message
  """
  @spec broadcast_node_messages(Message.t()) :: :ok | {:error, term}
  def broadcast_node_messages(message = %{node_id: node_id}) do
    PubSub.broadcast(@bridge_name, _node_topic(node_id), {:mysensors, :node_messages, message})
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
