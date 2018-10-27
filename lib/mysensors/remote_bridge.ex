defmodule MySensors.RemoteBridge do

  @moduledoc """
  A server handling communication with a remote MySensors application

  # Configuration

  Use `:remote_bridge` to configure the bridge.

      config :mysensors,
        remote_bridge: %{
          node: :'user@host',
          transport: 'uuid'
        }
  """

  # TODO implement a keep alive using Node.ping and GenServer's timeout callback


  use GenServer, start: {__MODULE__, :start_link, [:uuid, :config]}
  require Logger


  #########
  #  API
  #########

  @doc "Start the server"
  @spec start_link(String.t(), map) :: GenServer.on_start()
  def start_link(uuid, config), do: GenServer.start_link(__MODULE__, {uuid, config})


  @doc "Retrieve the UUID used by for the transport topic"
  @spec transport_uuid(String.t(), map, pid) :: String.t()
  def transport_uuid(_network_uuid, config, _server), do: config.transport



  ###############
  #  Internals
  ###############

  # Initialize the serial connection at server startup
  def init({_uuid, config}) do
    config.node
    |> Node.ping 

    {:ok, %{config: config}}
  end

end

