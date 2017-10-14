defmodule MySensors.DiscoveryManager do

  @moduledoc """
  A manager for discovery related events
  """

  use Supervisor


  @doc """
  Start the manager
  """
  def start_link(_) do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end


  # Initialize the manager
  def init(_) do
    Supervisor.init([], strategy: :one_for_one)
  end


  @doc """
  Add an handler
  """
  def add_handler(handler, args) do
    specs = handler.child_spec(args)
    Supervisor.start_child(__MODULE__, specs)
  end


  @doc """
  Notify the handlers
  """
  def notify(msg) do
    for {_, pid, _, _} <- Supervisor.which_children(__MODULE__) do
      GenServer.cast(pid, msg)
    end

    :ok
  end

end
