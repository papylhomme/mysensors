defmodule MySensors do
  @moduledoc """
  MySensors Application
  """

  use Application

  # Name of the registry mapping UUIDs to processes
  @registry_name MySensors.Registry


  # System services always started as partof the supervision tree
  @initial_children [
    {Registry, keys: :unique, name: @registry_name},
    MySensors.Bus,
    MySensors.TransportBus,
    %{id: :remote, start: {MySensors.Network, :start_link, [%{uuid: UUID.uuid5(:nil, "remote_network"), transport: {:remote, ""}}]}},
    {MySensors.Network, %{uuid: UUID.uuid5(:nil, "mqtt_bridge"), transport: {MySensors.MQTTBridge, %{}}}}
  ]


  @doc """
  Setup a GenServer `:via` tuple using the given uuid
  """
  @spec by_uuid(String.t()) :: GenServer.server()
  def by_uuid(uuid) do
    {:via, Registry, {@registry_name, uuid}}
  end


  @doc """
  Start the application
  """
  def start(_type, _args) do
    children =
      @initial_children
      |> _append_if_needed(Application.get_env(:mysensors, :serial_bridge, nil) != nil, [ {Nerves.UART, [name: Nerves.UART]}, MySensors.SerialBridge ])
      |> _append_if_needed(Application.get_env(:mysensors, :mqtt_bridge, nil) != nil, MySensors.MQTTBridge)

    opts = [strategy: :one_for_one, name: MySensors.Supervisor]
    Supervisor.start_link(children, opts)
  end


  # Helper to dynamically create the list of supervised children
  defp _append_if_needed(children, false, _child), do: children
  defp _append_if_needed(children, _, child) do
    case child do
      c when is_list c -> children ++ c
      c -> children ++ [ c ]
    end
  end

end
