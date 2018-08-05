defmodule MySensors.NetworksManager do
  @moduledoc """
  A manager for networks
  """

  use GenServer, start: {__MODULE__, :start_link, []}
  require Logger


  #########
  #  API
  #########

  def start_link() do
    GenServer.start_link(__MODULE__, {}, name: __MODULE__)
  end


  def networks() do
    GenServer.call(__MODULE__, :networks)
  end


  def start_network(id, transport) do
    GenServer.call(__MODULE__, {:start_network, id, transport})
  end


  def stop_network(uuid) do
    GenServer.call(__MODULE__, {:stop_network, uuid})
  end


  ###################
  #  Implementation
  ###################

  def init({}) do
    {:ok, supervisor} = DynamicSupervisor.start_link(strategy: :one_for_one)
    {:ok, %{supervisor: supervisor}}
  end


  def handle_call(:networks, _from, state) do
    res =
      state.supervisor
      |> DynamicSupervisor.which_children
      |> Enum.map(fn {_, pid, _, _} -> MySensors.Network.info(pid) end)

    {:reply, res, state}
  end


  def handle_call({:start_network, id, transport}, _from, state) do
    Logger.info "Starting network #{id}"

    res = DynamicSupervisor.start_child(state.supervisor, %{
      id: id,
      start: {MySensors.Network, :start_link, [%{id: id, uuid: UUID.uuid5(:nil, "#{id}"), transport: transport}]}
    })

    {:reply, res, state}
  end


  def handle_call({:stop_network, uuid}, _from, state) do
    child =
      state.supervisor
      |> DynamicSupervisor.which_children
      |> Enum.find(fn {_, pid, _, _} -> uuid == MySensors.Network.info(pid).uuid end)

    res =
      case child do
        {_, pid, _, _} -> DynamicSupervisor.terminate_child(state.supervisor, pid)
        _ -> nil
      end

    {:reply, res, state}
  end


end
