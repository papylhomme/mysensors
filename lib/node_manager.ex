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
    {:ok, tid} = :dets.open_file("#{__MODULE__}.db", [ram_file: true, auto_save: 10])

    {:ok, %{table: tid}}
  end


  # Handle node presentation
  def handle_cast({:node_presentation, node_spec = %{node_id: node_id}}, state = %{table: tid}) do
    case :dets.lookup(tid, node_id) do
      [] ->
        Logger.info "New node registration #{inspect node_spec}"
        IO.inspect :dets.insert(tid, {node_id, node_spec})

      _ ->
        Logger.warn "Updating node spec #{inspect node_spec}"
        IO.inspect :dets.insert(tid, {node_id, node_spec})
    end

    {:noreply, state}
  end


  # Handle node event
  def handle_cast({:node_event, %{node_id: node_id}}, state = %{table: tid}) do
    case :dets.lookup(tid, node_id) do
      []  -> :ok = MySensors.PresentationManager.request_presentation(node_id)
      _   -> Logger.warn "Handling event !"
    end

    {:noreply, state}
  end


end
