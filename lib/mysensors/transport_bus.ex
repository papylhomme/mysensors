defmodule MySensors.TransportBus do
  @moduledoc """
  PubSub implementation for bridges communication

  The registered name of the PubSub server can be configured using the `:transport_bus_name` config key:

      config :mysensors,
        transport_bus_name: CustomBusName
  """
  use MySensors.PubSub

  @bus_name Application.get_env(:mysensors, :transport_bus_name, __MODULE__)


  @doc """
  Defines the specification for a supervisor
  """
  def child_spec(_args) do
    Supervisor.child_spec(
      %{start: {Phoenix.PubSub.PG2, :start_link, [@bus_name, []]}, id: @bus_name},
      []
    )
  end


  def subscribe(topic), do: Phoenix.PubSub.subscribe(@bus_name, topic)
  def unsubscribe(topic), do: Phoenix.PubSub.unsubscribe(@bus_name, topic)
  def broadcast(topic, message), do: Phoenix.PubSub.broadcast(@bus_name, topic, message)

  topic_helpers(__MODULE__, :incoming, fn transport_uuid -> "transport_#{transport_uuid}_incoming" end)
  topic_helpers(__MODULE__, :outgoing, fn transport_uuid -> "transport_#{transport_uuid}_outgoing" end)

end
