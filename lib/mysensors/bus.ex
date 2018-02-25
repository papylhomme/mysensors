defmodule MySensors.Bus do
  alias Phoenix.PubSub

  @moduledoc """
  PubSub implementation for bridge communication
  """

  @bridge_name Application.get_env(:mysensors, :bus_name, __MODULE__)

  @doc """
  Subscribe the caller to the given topic
  """
  @spec subscribe(binary) :: :ok | {:error, term}
  def subscribe(topic) do
    PubSub.subscribe(@bridge_name, topic)
  end

  @doc """
  Broadcast a message to the given topic
  """
  @spec broadcast(binary, term) :: :ok | {:error, term}
  def broadcast(topic, message) do
    PubSub.broadcast(@bridge_name, topic, message)
  end

  @doc """
  Defines the specification for a supervisor
  """
  def child_spec(_args) do
    Supervisor.child_spec(
      %{start: {PubSub.PG2, :start_link, [@bridge_name, []]}, id: @bridge_name},
      []
    )
  end
end
