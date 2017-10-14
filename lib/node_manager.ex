defmodule MySensors.NodeManager do

  @moduledoc """
  Module responsible to track nodes on the network
  """

  use GenServer

  require Logger


  @doc """
  Start the manager
  """
  def start_link(_) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end


  @doc """
  Process a node presentation
  """
  def on_node_presentation(node_spec) do
    GenServer.cast(__MODULE__, {:node_presentation, node_spec})
  end


  @doc """
  Process a node event
  """
  def on_node_event(msg) do
    GenServer.cast(__MODULE__, {:node_event, msg})
  end


  # Initialize the manager
  def init(_) do
    {:ok, %{nodes: %{}}}
  end


  # Handle node presentation
  def handle_cast({:node_presentation, node_spec}, state) do
    new_state =
      case Map.has_key?(state.nodes, node_spec.node_id) do
        true ->
          Logger.warn "Updating node spec #{inspect node_spec}"
          put_in(state, [:nodes, node_spec.node_id], node_spec)
        false ->
          Logger.info "New node registration #{inspect node_spec}"
          put_in(state, [:nodes, node_spec.node_id], node_spec)
      end

    {:noreply, new_state}
  end


  # Handle node event
  def handle_cast({:node_event, msg}, state) do
    case Map.has_key?(state.nodes, msg.node_id) do
      true -> Logger.warn "Handling event !"
      false -> :ok = MySensors.PresentationManager.request_presentation(msg.node_id)
    end

    {:noreply, state}
  end


end
