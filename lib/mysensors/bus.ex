defmodule MySensors.Bus do
  alias Phoenix.PubSub

  @moduledoc """
  PubSub implementation for bridge communication
  """

  @bridge_name Application.get_env(:mysensors, :bus_name, __MODULE__)

  @doc """
  Subscribe the caller to the `node`'s topic
  """
  @spec subscribe_node(any) :: :ok | {:error, term}
  def subscribe_node(node_id) do
    PubSub.subscribe(@bridge_name, _node_topic(node_id))
  end

  @doc """
  Broadcast a log message
  """
  @spec broadcast_log(any) :: :ok | {:error, term}
  def broadcast_log(message) do
    PubSub.broadcast(@bridge_name, "gwlog", {:mysensors, :log, message})
  end

  @doc """
  Broadcast a node message
  """
  @spec broadcast_node_message(any) :: :ok | {:error, term}
  def broadcast_node_message(message = %{node_id: node_id}) do
    PubSub.broadcast(@bridge_name, _node_topic(node_id), {:mysensors, :message, message})
  end

  @doc """
  Broadcast a sensor event
  """
  @spec broadcast_sensor_event(any) :: :ok | {:error, term}
  def broadcast_sensor_event(event) do
    PubSub.broadcast(@bridge_name, "sensors_events", {:mysensors, :sensor_events, event})
  end

  @doc """
  Broadcast a node event
  """
  @spec broadcast_node_event(any) :: :ok | {:error, term}
  def broadcast_node_event(event) do
    PubSub.broadcast(@bridge_name, "nodes_events", {:mysensors, :node_events, event})
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
