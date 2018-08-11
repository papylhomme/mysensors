defmodule MySensors.Events do
  alias MySensors.Bus
  alias MySensors.Network


  # TODO use a macro for the events

  defmodule NetworkRegistered do
    @moduledoc "Event generated when a new network is registered"

    # Event struct
    defstruct network: nil, config: nil

    @typedoc "The event struct"
    @type t :: %__MODULE__{network: MySensors.uuid, config: Network.config}

    @doc "Create and broadcast an `#{__MODULE__}` event"
    @spec broadcast(MySensors.uuid, Network.config) :: :ok | {:error, term}
    def broadcast(network, config) do
      %__MODULE__{network: network, config: config}
      |> Bus.broadcast_networks_events()
    end
  end


  defmodule NetworkUnregistered do
    @moduledoc "Event generated when a network is unregistered"

    # Event struct
    defstruct network: nil

    @typedoc "The event struct"
    @type t :: %__MODULE__{network: MySensors.uuid}

    @doc "Create and broadcast an `#{__MODULE__}` event"
    @spec broadcast(MySensors.uuid) :: :ok | {:error, term}
    def broadcast(network) do
      %__MODULE__{network: network}
      |> Bus.broadcast_networks_events()
    end
  end


  defmodule NetworkStatusChanged do
    @moduledoc "Event generated when the status of a network has changed"

    # Event struct
    defstruct network: nil, status: nil

    @typedoc "The event struct"
    @type t :: %__MODULE__{network: MySensors.uuid, status: Network.status}


    @doc "Create and broadcast an `#{__MODULE__}` event"
    @spec broadcast(MySensors.uuid, Network.status) :: :ok | {:error, term}
    def broadcast(network, status) do
      %__MODULE__{network: network, status: status}
      |> Bus.broadcast_networks_events()
    end
  end

end
