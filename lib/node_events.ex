defmodule MySensors.NodeEvents do

  alias MySensors.Node


  @moduledoc """
  An event dispatcher for node events built with `MySensors.PubSub`
  """

  use MySensors.PubSub


  @typedoc "Types of node events"
  @type node_events :: Node.NodeDiscoveredEvent.t | Node.NodeUpdatedEvent.t


  @doc """
  Dispatches a node `event`
  """
  @spec on_node_event(Node.event) :: :ok
  def on_node_event(event = %{node_id: node_id}) do
    dispatch_event(@registry, node_id, event)
  end


  @doc """
  Registers a global event handler
  """
  @spec register_nodes_handler() :: :ok
  def register_nodes_handler do
    register(@registry, :global)
  end


  @doc """
  Unregisters a global event handler
  """
  @spec unregister_nodes_handler() :: :ok
  def unregister_nodes_handler do
    unregister(@registry, :global)
  end


  @doc """
  Registers as event handler for the given `nodes`

  As a convenience, `nodes` can be a list or a single element.
  """
  @spec register_nodes_handler(MySensors.Node.t | [MySensors.Node.t]) :: :ok
  def register_nodes_handler(nodes) when is_list(nodes) do
    Enum.each(nodes, fn node -> register_nodes_handler(node) end)
  end

  def register_nodes_handler(_node = %{node_id: node_id}) do
    register(@registry, node_id)
  end


  @doc """
  Unregisters as event handler from the given `nodes`

  As a convenience, `nodes` can be a list or a single element.
  """
  @spec unregister_nodes_handler(Node.t | [Node.t]) :: :ok
  def unregister_nodes_handler(nodes) when is_list(nodes) do
    Enum.each(nodes, fn node -> unregister_nodes_handler(node) end)
  end

  def unregister_nodes_handler(_node = %{node_id: node_id}) do
    unregister(@registry, node_id)
  end


end

