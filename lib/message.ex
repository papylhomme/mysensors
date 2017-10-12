defmodule MySensors.Message do

  @moduledoc """
  A MySensors message
  """

  defstruct node_id: nil, child_sensor_id: nil, command: nil, ack: nil, type: nil, payload: nil


  require Logger


  @doc """
  Create a new message from parameters
  """
  def new(node_id, child_sensor_id, command, ack, type, payload) do
    %__MODULE__{
      node_id: node_id,
      child_sensor_id: child_sensor_id,
      command: command,
      ack: ack,
      type: type,
      payload: payload
    }
  end


  @doc """
  Parse a line using the MySensors Serial API
  """
  def parse(input) do
    try do
      [node_id, child_sensor_id, command, ack, type, payload] = String.split(input, ~r/[^a-zA-Z0-9-_]/, parts: 6)

      node_id = node_id |> String.to_integer
      child_sensor_id = child_sensor_id |> String.to_integer
      command = command |> String.to_integer
      ack = ack == "1"
      type = type |> String.to_integer

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
          x             -> x
        end
  
      %__MODULE__{
        node_id: node_id,
        child_sensor_id: child_sensor_id,
        command: cmd,
        ack: ack,
        type: type,
        payload: payload
      }
    rescue
      e -> {:error, input, e, System.stacktrace}
    end
  end


  @doc """
  Serialize a message using the MySensors Serial API
  """
  def serialize(msg) do
    cmd =
      case msg.command do
        :presentation -> 0
        :set          -> 1
        :req          -> 2
        :internal     -> 3
        x -> x
      end

    t =
      case msg.command do
        :presentation -> msg.type |> MySensors.Types.presentation_id
        :set          -> msg.type |> MySensors.Types.variable_id
        :req          -> msg.type |> MySensors.Types.variable_id
        :internal     -> msg.type |> MySensors.Types.internal_id
        x             -> x
      end

    "#{msg.node_id};#{msg.child_sensor_id};#{cmd};#{if msg.ack, do: 1, else: 0};#{t};#{msg.payload}"
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

