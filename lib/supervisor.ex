defmodule MySensors.Supervisor do

  @moduledoc """
  Application supervisor
  """

  use Supervisor


  @doc """
  Start the supervisor and register it's name
  """
  def start_link do
    Supervisor.start_link(__MODULE__, nil, name: __MODULE__)
  end


  @doc """
  Start the children
  """
  def init(nil) do
    Supervisor.init([
      {Nerves.UART, [name: Nerves.UART]},
      {MySensors.Gateway, Application.get_env(:mysensors, :uart)},
    ], strategy: :one_for_one)
  end

end

