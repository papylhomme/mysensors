defmodule MySensors.Message do

  @moduledoc """
  A MySensors message
  """

  defstruct node_id: nil, child_sensor_id: nil, command: nil, ack: nil, type: nil, payload: nil


  require Logger


  @doc """
  Create a new message from raw parameters
  """
  def new(command, node_id, child_sensor_id, ack, type, payload) do
    cmd =
      case command do
        0 -> :presentation
        1 -> :set
        2 -> :req
        3 -> :internal
        x -> x
      end

    type =
      case cmd do
        :presentation -> type |> MySensors.Types.presentation_type_id
        :set          -> type |> MySensors.Types.variable_type_id
        :req          -> type |> MySensors.Types.variable_type_id
        :internal     -> type |> MySensors.Types.internal_type_id
      end

    %__MODULE__{
      node_id: node_id,
      child_sensor_id: child_sensor_id,
      command: cmd,
      ack: ack,
      type: type,
      payload: payload
    }
  end


  @doc """
  Parse a line from a MySensors Serial Gateway
  """
  def parse(input) do
    try do
      [node_id, child_sensor_id, command, ack, type, payload] = String.split(input, ~r/[^a-zA-Z0-9-_]/, parts: 6)

      node_id = node_id |> String.to_integer
      child_sensor_id = child_sensor_id |> String.to_integer
      command = command |> String.to_integer
      ack = ack == "1"
      type = type |> String.to_integer

      new(command, node_id, child_sensor_id, ack, type, payload)
    rescue
      e -> {:error, e, System.stacktrace}
    end
  end

end


defimpl String.Chars, for: MySensors.Message do

  @moduledoc """
  User friendly formatting of MySensors messages
  """


  @doc """
  Format a message into a user readable string
  """
  def to_string(msg) do
    """
    Node #{msg.node_id} / Sensor #{msg.child_sensor_id}
    Command: #{msg.command}
    Type: #{msg.type}
    Payload: #{msg.payload}
    #{if msg.ack, do: "WITH ack", else: "WITHOUT ack"}
    """
  end

end

