defmodule MySensors.Message do

  @moduledoc """
  A MySensors message
  """
  defstruct node_id: nil, child_sensor_id: nil, command: nil, ack: nil, type: nil, payload: nil


  alias MySensors.Types

  @typedoc "A message"
  @type t :: %__MODULE__{node_id: Types.id, child_sensor_id: Types.id, command: Types.command, ack: boolean, type: Types.type, payload: String.t}

  @typedoc "A presentation message"
  @type presentation :: %__MODULE__{node_id: Types.id, child_sensor_id: Types.id, command: :presentation, ack: boolean, type: Types.type, payload: String.t}

  @typedoc "A sensor event"
  @type sensor_updated :: %__MODULE__{node_id: Types.id, child_sensor_id: Types.id, command: :set, ack: boolean, type: Types.type, payload: String.t}

  @typedoc "A discovery event"
  @type discovery :: %__MODULE__{node_id: Types.id, child_sensor_id: Types.id, command: :internal, ack: boolean, type: I_DISCOVER_RESPONSE, payload: String.t}


  require Logger


  @doc """
  Create a new message from parameters
  """
  @spec new(Types.id, Types.id, Types.command, Types.type, String.t, boolean) :: t
  def new(node_id, child_sensor_id, command, type, payload, ack) do
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
  @spec parse(String.t) :: t
  def parse(input) do
    try do
      [node_id, child_sensor_id, command, ack, type, payload] = String.split(input, ~r/[^a-zA-Z0-9-_]/, parts: 6)

      node_id = node_id |> String.to_integer
      child_sensor_id = child_sensor_id |> String.to_integer
      command = command |> String.to_integer
      ack = ack == "1"
      type = type |> String.to_integer

      {cmd, type} =
        case command do
          0 -> {:presentation,  type |> Types.presentation_type}
          1 -> {:set,           type |> Types.variable_type}
          2 -> {:req,           type |> Types.variable_type}
          3 -> {:internal,      type |> Types.internal_type}
          _ -> {:unknown,       nil}
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
  @spec serialize(t) :: String.t
  def serialize(msg) do
    {cmd, t} =
      case msg.command do
        :presentation -> {0, msg.type |> Types.presentation_id}
        :set          -> {1, msg.type |> Types.variable_id}
        :req          -> {2, msg.type |> Types.variable_id}
        :internal     -> {3, msg.type |> Types.internal_id}
        _             -> {:unknown, nil}
      end

    "#{msg.node_id};#{msg.child_sensor_id};#{cmd};#{if msg.ack, do: 1, else: 0};#{t};#{msg.payload}"
  end

end


defimpl String.Chars, for: MySensors.Message do
  alias MySensors.Message

  @moduledoc """
  User friendly formatting of MySensors messages
  """


  @doc """
  Format a message into a user readable string
  """
  @spec to_string(Message.t) :: String.t
  def to_string(msg) do
    "#{inspect msg}\n-> RAW: #{Message.serialize(msg)}"
  end

end

