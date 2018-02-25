defmodule MySensors.TransportBus do
  alias MySensors.Message
  alias Phoenix.PubSub

  @moduledoc """
  PubSub implementation for bridge communication
  """

  @bridge_name Application.get_env(:mysensors, :transport_bus_name, __MODULE__)

  @doc """
  Broadcast a new incoming message
  """
  @spec broadcast_incoming(Message.t()) :: :ok | {:error, term}
  def broadcast_incoming(message) do
    PubSub.broadcast(@bridge_name, "incoming", {:mysensors_incoming, message})
  end

  @doc """
  Broadcast a new outgoing message
  """
  @spec broadcast_outgoing(Message.t()) :: :ok | {:error, term}
  def broadcast_outgoing(message) do
    PubSub.broadcast(@bridge_name, "outgoing", {:mysensors_outgoing, message})
  end

  @doc """
  Subscribe the caller to incoming messages
  """
  @spec subscribe_incoming() :: :ok | {:error, term}
  def subscribe_incoming do
    PubSub.subscribe(@bridge_name, "incoming")
  end

  @doc """
  Subscribe the caller to outgoing messages
  """
  @spec subscribe_outgoing() :: :ok | {:error, term}
  def subscribe_outgoing do
    PubSub.subscribe(@bridge_name, "outgoing")
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
