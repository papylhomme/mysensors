defmodule MySensors.DiscoveryManager do

  @moduledoc """
  A manager for discovery related events

  The implementation relies on a Supervisor notifying GenServers using `GenServer.cast(pid, msg)`
  """

  use Supervisor
  require Logger


  @doc """
  Start the manager
  """
  @spec start_link(nil) :: GenServer.on_start
  def start_link(_) do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end


  @doc """
  Add an handler
  """
  @spec add_handler(module, any) :: Supervisor.on_start_child
  def add_handler(handler, args) do
    specs = handler.child_spec(args)
    Supervisor.start_child(__MODULE__, specs)
  end


  @doc """
  Notify the handlers
  """
  @spec notify(MySensors.Message.discovery) :: :ok
  def notify(msg) do
    for {_, pid, _, _} <- Supervisor.which_children(__MODULE__) do
      GenServer.cast(pid, msg)
    end

    :ok
  end


  @doc """
  Discover nodes on the network
  """
  @spec discover() :: :ok
  def discover do
    Logger.info "Sending discover request"
    MySensors.Gateway.send_message(255, 255, :internal, false, I_DISCOVER_REQUEST)
    :ok
  end


  @doc """
  Discover sensors on the network and request presentation for each of them
  """
  @spec scan() :: :ok
  def scan do
    Logger.info "Starting scan of MySensors network..."

    # Register scan discovery handler and start the scan
    add_handler(__MODULE__.ScanDiscoveryHandler, [])
    discover()

    # Manually request presentation from the gateway
    MySensors.PresentationManager.request_presentation(0)
    :ok
  end


  # Initialize the manager
  def init(_) do
    Supervisor.init([], strategy: :one_for_one)
  end


  defmodule ScanDiscoveryHandler do

    @moduledoc """
    An handler for `MySensors.DiscoveryManager` requesting presentation upon discovery
    """

    use GenServer, restart: :temporary

    @timeout 5000

    @doc """
    Start the server
    """
    @spec start_link(any) :: GenServer.on_start
    def start_link(_opts) do
      GenServer.start_link(__MODULE__, [])
    end


    # Init the server
    def init(_) do
      {:ok, %{}, @timeout}
    end


    # Handle discover response
    def handle_cast(msg = %{type: I_DISCOVER_RESPONSE}, state) do
      Logger.info "Node #{msg.node_id} discovered"
      MySensors.PresentationManager.request_presentation(msg.node_id)
      {:noreply, state, @timeout}
    end


    # Fallback
    def handle_cast(_, state) do
      {:noreply, state, @timeout}
    end


    # Timeout to stop the server
    def handle_info(:timeout, state) do
      Logger.info "Network scan finished"
      {:stop, :shutdown, state}
    end

  end


end
