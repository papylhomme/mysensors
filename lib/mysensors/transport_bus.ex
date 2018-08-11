defmodule MySensors.TransportBus do
  use MySensors.PubSub

  @moduledoc """
  PubSub implementation for bridges communication

  The registered name of the PubSub server can be configured using the `:transport_bus_name` config key:

      config :mysensors,
        transport_bus_name: CustomBusName
  """

  @bridge_name Application.get_env(:mysensors, :transport_bus_name, __MODULE__)


  topic_helpers(@bridge_name, :incoming, fn transport_uuid -> "incoming#{transport_uuid}" end)
  topic_helpers(@bridge_name, :outgoing, fn transport_uuid -> "outgoing#{transport_uuid}" end)



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
