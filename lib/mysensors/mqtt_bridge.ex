defmodule MySensors.MQTTBridge do
  alias MySensors.TransportBus
  alias MySensors.Message
  alias MySensors.Types


  # Default config values
  @default %{
    client_id: "mysensors_client_id",
    host: "localhost",
    port: 1883,
    root: "mysensors"
  }

  @moduledoc """
  A server handling communication with a [MySensors MQTT Gateway](https://www.mysensors.org/build/mqtt_gateway)

  # Configuration

  Use `:mqtt_bridge` to configure the bridge. Any missing key will be filled using the default values used below.

      config :mysensors,
        mqtt_bridge: %{
          client_id: #{inspect @default.client_id},
          host: #{inspect @default.host},
          port: #{inspect @default.port},
          root: #{inspect @default.root}
        }

  """

  use GenServer, start: {__MODULE__, :start_link, []}
  require Logger



  #########
  #  API
  #########

  @doc """
  Start the server
  """
  @spec start_link :: GenServer.on_start()
  def start_link do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end



  ###############
  #  Internals
  ###############

  # Initialize the serial connection at server startup
  def init(nil) do
    # Init config
    config = Application.get_env(:mysensors, :mqtt_bridge)
    if is_nil(config), do: raise("Missing configuration key :mqtt_bridge")

    config = %{
      client_id: Map.get(config, :client_id, @default.client_id),
      host: Map.get(config, :host, @default.host),
      port:  Map.get(config, :port, @default.port),
      root: Map.get(config, :port, @default.root),
    }

    # Init MQTT Client
    Logger.info("Starting mqtt bridge '#{config.client_id}' on #{config.host}##{config.port}")
    Tortoise.Supervisor.start_child(
      client_id: config.client_id,
      handler: {__MODULE__.Handler, []},
      server: {:tcp, config.host, config.port},
      subscriptions: [{"#{config.root}-out/#", 0}])

    # Transport subscription
    TransportBus.subscribe_outgoing()

    {:ok, %{config: config}}
  end


  # Handle outgoing messages
  def handle_info({:mysensors, :outgoing, message}, state) do
    {command, type} =
      case message.command do
        :presentation -> {0, message.type |> Types.presentation_id()}
        :set -> {1, message.type |> Types.variable_id()}
        :req -> {2, message.type |> Types.variable_id()}
        :internal -> {3, message.type |> Types.internal_id()}
        _ -> {:unknown, nil}
      end

    topics = [
      "mysensors-in",
      message.node_id,
      message.child_sensor_id,
      command,
      (if message.ack, do: 1, else: 0),
      type
    ]

    Tortoise.publish(state.config.client_id, Enum.join(topics, "/"), message.payload, qos: 0)
    {:noreply, state}
  end

  # Fallback for unknown messages
  def handle_info(msg, state) do
    Logger.warn("Unknown message: #{inspect(msg)}")
    {:noreply, state}
  end


  defmodule Handler do
    @moduledoc false
    @behaviour Tortoise.Handler


    def init(_opts) do
      {:ok, nil}
    end

    def connection(_status, state) do
      {:ok, state}
    end

    def subscription(_status, _topic, state) do
      {:ok, state}
    end

    def handle_message(["mysensors-out" | topic], payload, state) do
      case topic do
        [_node_id, _sensor_id, _command, _ack, _type] ->
          topic
          |> List.insert_at(-1, payload)
          |> Enum.join(";")
          |> Message.parse
          |> TransportBus.broadcast_incoming

        _ -> Logger.warn "Received unexpected message from #{inspect topic}: #{inspect payload}"
      end

      {:ok, state}
    end

    def terminate(_reason, _state) do
      :ok
    end

  end

end
