defmodule MySensors.Bus do
  @moduledoc """
  PubSub implementation for API communication

  The registered name of the PubSub server can be configured using the `:bus_name` config key:

      config :mysensors,
        bus_name: CustomBusName
  """

  alias Phoenix.PubSub

  @bus_name Application.get_env(:mysensors, :bus_name, __MODULE__)


  @doc "Defines the specification for a supervisor"
  @spec child_spec(any) :: Supervisor.child_spec()
  def child_spec(_args) do
    Supervisor.child_spec(
      %{start: {PubSub.PG2, :start_link, [@bus_name, []]}, id: @bus_name},
      []
    )
  end


  @doc "Subscribe to the `topic`'s messages"
  @spec subscribe(binary) :: :ok | {:error, term()}
  def subscribe(topic), do: PubSub.subscribe(@bus_name, topic)

  @doc "Unsubscribe from the `topic`'s messages"
  @spec unsubscribe(binary) :: :ok | {:error, term()}
  def unsubscribe(topic), do: PubSub.unsubscribe(@bus_name, topic)

  @doc "Broadcast a `message` to the `topic`"
  @spec broadcast(binary, any) :: :ok | {:error, term()}
  def broadcast(topic, message), do: PubSub.broadcast(@bus_name, topic, message)

end
