defmodule MySensors do
  @moduledoc """
  MySensors Application
  """

  use Application


  @initial_children [
    MySensors.Bus,
    MySensors.TransportBus,
    MySensors.Network
  ]


  @doc """
  Start the application
  """
  def start(_type, _args) do
    children =
      @initial_children
      |> _append_if_needed(Application.get_env(:mysensors, :gateway, true) == true, MySensors.Gateway)
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
