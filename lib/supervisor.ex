defmodule MySensors.Supervisor do

  @moduledoc """
  Application supervisor
  """

  use Supervisor


  @doc """
  Start the supervisor and register it's name
  """
  @spec start_link() :: Supervisor.on_start
  def start_link do
    Supervisor.start_link(__MODULE__, nil, name: __MODULE__)
  end


  @doc """
  Start the children
  """
  @spec init(nil) :: {:ok, tuple}
  def init(nil) do
    Supervisor.init([
      {Nerves.UART, [name: Nerves.UART]},
      MySensors.NodeEvents,
      MySensors.NodeManager,
      MySensors.PresentationManager,
      MySensors.DiscoveryManager,
      {MySensors.Gateway, Application.get_env(:mysensors, :uart)},
    ], strategy: :one_for_one)
  end

end

