defmodule MySensors.TransportBus do
  use MySensors.PubSub

  @moduledoc """
  PubSub implementation for bridge communication
  """

  @bridge_name Application.get_env(:mysensors, :transport_bus_name, __MODULE__)


  topic_helpers(@bridge_name, :incoming, :incoming)
  topic_helpers(@bridge_name, :outgoing, :outgoing)



  @doc """
  Defines the specification for a supervisor
  """
  def child_spec(_args) do
    Supervisor.child_spec(
      %{start: {Phoenix.PubSub.PG2, :start_link, [@bridge_name, []]}, id: @bridge_name},
      []
    )
  end
end
