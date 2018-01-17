defmodule MySensors.Types do

  @moduledoc """
  Helper to convert from/to MySensors ID to atoms

  Extracted from [MySensors Serial API 2.0](https://www.mysensors.org/download/serial_api_20)

  TODO move this to (D)ETS and implement an helper to parse the website and update the storage ?
  """

  @typedoc "MySensors command type"
  @type command :: :presentation | :set | :req | :internal | :unknown

  @typedoc "MySensors ID"
  @type id :: 0..255

  @typedoc "MySensors Type"
  @type type :: atom

  @typedoc "MySensors internal command type"
  @type internal :: type

  @typedoc "MySensors sensor type"
  @type sensor :: type

  @typedoc "MySensors variable type"
  @type variable :: type


  # Command type
  def command do
    [:presentation, :set, :req, :internal]
  end


  @doc """
  Get a command type from the given ID
  """
  @spec command_type(id) :: command
  def command_type(id) do
    command() |> Enum.at(id)
  end



  @doc """
  Get a command ID from the given type
  """
  @spec command_id(command) :: id
  def command_id(type) do
    command() |> Enum.find_index(fn t -> t == type end)
  end


  # Internal types
  def internal do
    [
      {I_BATTERY_LEVEL, 0, "Use this to report the battery level (in percent 0-100)."},
      {I_TIME, 1, "Sensors can request the current time from the Controller using this message. The time will be reported as the seconds since 1970"},
      {I_VERSION, 2, "Used to request gateway version from controller."},
      {I_ID_REQUEST, 3, "Use this to request a unique node id from the controller."},
      {I_ID_RESPONSE, 4, "Id response back to node. Payload contains node id."},
      {I_INCLUSION_MODE, 5, "Start/stop inclusion mode of the Controller (1=start, 0=stop)."},
      {I_CONFIG, 6, "Config request from node. Reply with (M)etric or (I)mperal back to sensor."},
      {I_FIND_PARENT, 7, "When a sensor starts up, it broadcast a search request to all neighbor nodes. They reply with a I_FIND_PARENT_RESPONSE."},
      {I_FIND_PARENT_RESPONSE, 8, "Reply message type to I_FIND_PARENT request."},
      {I_LOG_MESSAGE, 9, "Sent by the gateway to the Controller to trace-log a message"},
      {I_CHILDREN, 10, "A message that can be used to transfer child sensors (from EEPROM routing table) of a repeating node."},
      {I_SKETCH_NAME, 11, "Optional sketch name that can be used to identify sensor in the Controller GUI"},
      {I_SKETCH_VERSION, 12, "Optional sketch version that can be reported to keep track of the version of sensor in the Controller GUI."},
      {I_REBOOT, 13, "Used by OTA firmware updates. Request for node to reboot."},
      {I_GATEWAY_READY, 14, "Send by gateway to controller when startup is complete."},
      {I_SIGNING_PRESENTATION, 15, "Provides signing related preferences (first byte is preference version)."},
      {I_NONCE_REQUEST, 16, "Used between sensors when requesting nonce."},
      {I_NONCE_RESPONSE, 17, "Used between sensors for nonce response."},
      {I_HEARTBEAT_REQUEST, 18, "Heartbeat request"},
      {I_PRESENTATION, 19, "Presentation message"},
      {I_DISCOVER_REQUEST, 20, "Discover request"},
      {I_DISCOVER_RESPONSE, 21, "Discover response"},
      {I_HEARTBEAT_RESPONSE, 22, "Heartbeat response"},
      {I_LOCKED, 23, "Node is locked (reason in string-payload)"},
      {I_PING, 24, "Ping sent to node, payload incremental hop counter"},
      {I_PONG, 25, "In return to ping, sent back to sender, payload incremental hop counter"},
      {I_REGISTRATION_REQUEST, 26, "Register request to GW"},
      {I_REGISTRATION_RESPONSE, 27, "Register response from GW"},
      {I_DEBUG, 28, "Debug message"},
    ]
  end


  @doc """
  Get a type from the given ID
  """
  @spec internal_type(id) :: internal
  def internal_type(value) do
    value |> _lookup_by_value(internal())
  end


  @doc """
  Get an ID from the given type
  """
  @spec internal_id(internal) :: id
  def internal_id(type) do
    type |> _lookup_by_type(internal())
  end




  # Presentation types from MySensors.org
  def presentation do
    [
      {S_DOOR, 0, "Door and window sensors	V_TRIPPED, V_ARMED"},
      {S_MOTION, 1, "Motion sensors	V_TRIPPED, V_ARMED"},
      {S_SMOKE, 2, "Smoke sensor	V_TRIPPED, V_ARMED"},
      {S_BINARY, 3, "Binary device (on/off)	V_STATUS, V_WATT"},
      {S_DIMMER, 4, "Dimmable device of some kind	V_STATUS (on/off), V_PERCENTAGE (dimmer level 0-100), V_WATT"},
      {S_COVER, 5, "Window covers or shades	V_UP, V_DOWN, V_STOP, V_PERCENTAGE"},
      {S_TEMP, 6, "Temperature sensor	V_TEMP, V_ID"},
      {S_HUM, 7, "Humidity sensor	V_HUM"},
      {S_BARO, 8, "Barometer sensor (Pressure)	V_PRESSURE, V_FORECAST"},
      {S_WIND, 9, "Wind sensor	V_WIND, V_GUST, V_DIRECTION"},
      {S_RAIN, 10, "Rain sensor	V_RAIN, V_RAINRATE"},
      {S_UV, 11, "UV sensor	V_UV"},
      {S_WEIGHT, 12, "Weight sensor for scales etc.	V_WEIGHT, V_IMPEDANCE"},
      {S_POWER, 13, "Power measuring device, like power meters	V_WATT, V_KWH, V_VAR, V_VA, V_POWER_FACTOR"},
      {S_HEATER, 14, "Heater device	V_HVAC_SETPOINT_HEAT, V_HVAC_FLOW_STATE, V_TEMP, V_STATUS"},
      {S_DISTANCE, 15, "Distance sensor	V_DISTANCE, V_UNIT_PREFIX"},
      {S_LIGHT_LEVEL, 16, "Light sensor	V_LIGHT_LEVEL (uncalibrated percentage), V_LEVEL (light level in lux)"},
      {S_ARDUINO_NODE, 17, "Arduino node device"},
      {S_ARDUINO_REPEATER_NODE, 18, "Arduino repeating node device"},
      {S_LOCK, 19, "Lock device	V_LOCK_STATUS"},
      {S_IR, 20, "Ir sender/receiver device	V_IR_SEND, V_IR_RECEIVE, V_IR_RECORD"},
      {S_WATER, 21, "Water meter	V_FLOW, V_VOLUME"},
      {S_AIR_QUALITY, 22, "Air quality sensor e.g. MQ-2	V_LEVEL, V_UNIT_PREFIX"},
      {S_CUSTOM, 23, "Use this for custom sensors where no other fits."},
      {S_DUST, 24, "Dust level sensor	V_LEVEL, V_UNIT_PREFIX"},
      {S_SCENE_CONTROLLER, 25, "Scene controller device	V_SCENE_ON, V_SCENE_OFF"},
      {S_RGB_LIGHT, 26, "RGB light	V_RGB, V_WATT"},
      {S_RGBW_LIGHT, 27, "RGBW light (with separate white component)	V_RGBW, V_WATT"},
      {S_COLOR_SENSOR, 28, "Color sensor	V_RGB"},
      {S_HVAC, 29, "Thermostat/HVAC device	V_STATUS, V_TEMP, V_HVAC_SETPOINT_HEAT, V_HVAC_SETPOINT_COOL, V_HVAC_FLOW_STATE, V_HVAC_FLOW_MODE, V_HVAC_SPEED"},
      {S_MULTIMETER, 30, "Multimeter device	V_VOLTAGE, V_CURRENT, V_IMPEDANCE"},
      {S_SPRINKLER, 31, "Sprinkler device	V_STATUS (turn on/off), V_TRIPPED (if fire detecting device)"},
      {S_WATER_LEAK, 32, "Water leak sensor	V_TRIPPED, V_ARMED"},
      {S_SOUND, 33, "Sound sensor	V_LEVEL (in dB), V_TRIPPED, V_ARMED"},
      {S_VIBRATION, 34, "Vibration sensor	V_LEVEL (vibration in Hz), V_TRIPPED, V_ARMED"},
      {S_MOISTURE, 35, "Moisture sensor	V_LEVEL (water content or moisture in percentage?), V_TRIPPED, V_ARMED"},
      {S_INFO, 36, "LCD text device	V_TEXT"},
      {S_GAS, 37, "Gas meter	V_FLOW, V_VOLUME"},
      {S_GPS, 38, "GPS Sensor	V_POSITION"},
      {S_WATER_QUALITY, 39, "Water quality sensor	V_TEMP, V_PH, V_ORP, V_EC, V_STATUS"},
    ]
  end


  @doc """
  Get a type from the given ID
  """
  @spec presentation_type(id) :: sensor
  def presentation_type(value) do
    value |> _lookup_by_value(presentation())
  end


  @doc """
  Get an ID from the given type
  """
  @spec presentation_id(sensor) :: id
  def presentation_id(type) do
    type |> _lookup_by_type(presentation())
  end



  # Variables types from MySensors.org
  def variable do
    [
      {V_TEMP, 0, "Temperature	S_TEMP, S_HEATER, S_HVAC, S_WATER_QUALITY"},
      {V_HUM, 1, "Humidity	S_HUM"},
      {V_STATUS, 2, "Binary status. 0=off 1=on	S_BINARY, S_DIMMER, S_SPRINKLER, S_HVAC, S_HEATER, S_WATER_QUALITY"},
      {V_PERCENTAGE, 3, "Percentage value. 0-100 (%)	S_DIMMER, S_COVER"},
      {V_PRESSURE, 4, "Atmospheric Pressure	S_BARO"},
      {V_FORECAST, 5, "Whether forecast. One of 'stable', 'sunny', 'cloudy', 'unstable', 'thunderstorm' or 'unknown'	S_BARO"},
      {V_RAIN, 6, "Amount of rain	S_RAIN"},
      {V_RAINRATE, 7, "Rate of rain	S_RAIN"},
      {V_WIND, 8, "Windspeed	S_WIND"},
      {V_GUST, 9, "Gust	S_WIND"},
      {V_DIRECTION, 10, "Wind direction 0-360 (degrees)	S_WIND"},
      {V_UV, 11, "UV light level	S_UV"},
      {V_WEIGHT, 12, "Weight (for scales etc)	S_WEIGHT"},
      {V_DISTANCE, 13, "Distance	S_DISTANCE"},
      {V_IMPEDANCE, 14, "Impedance value	S_MULTIMETER, S_WEIGHT"},
      {V_ARMED, 15, "Armed status of a security sensor. 1=Armed, 0=Bypassed	S_DOOR, S_MOTION, S_SMOKE, S_SPRINKLER, S_WATER_LEAK, S_SOUND, S_VIBRATION, S_MOISTURE"},
      {V_TRIPPED, 16, "Tripped status of a security sensor. 1=Tripped, 0=Untripped	S_DOOR, S_MOTION, S_SMOKE, S_SPRINKLER, S_WATER_LEAK, S_SOUND, S_VIBRATION, S_MOISTURE"},
      {V_WATT, 17, "Watt value for power meters	S_POWER, S_BINARY, S_DIMMER, S_RGB_LIGHT, S_RGBW_LIGHT"},
      {V_KWH, 18, "Accumulated number of KWH for a power meter	S_POWER"},
      {V_SCENE_ON, 19, "Turn on a scene	S_SCENE_CONTROLLER"},
      {V_SCENE_OFF, 20, "Turn of a scene	S_SCENE_CONTROLLER"},
      {V_HVAC_FLOW_STATE, 21, "Mode of header. One of 'Off', 'HeatOn', 'CoolOn', or 'AutoChangeOver'	S_HVAC, S_HEATER"},
      {V_HVAC_SPEED, 22, "HVAC/Heater fan speed ('Min', 'Normal', 'Max', 'Auto')	S_HVAC, S_HEATER"},
      {V_LIGHT_LEVEL, 23, "Uncalibrated light level. 0-100%. Use V_LEVEL for light level in lux.	S_LIGHT_LEVEL"},
      {V_VAR1, 24, "Custom value	Any device"},
      {V_VAR2, 25, "Custom value	Any device"},
      {V_VAR3, 26, "Custom value	Any device"},
      {V_VAR4, 27, "Custom value	Any device"},
      {V_VAR5, 28, "Custom value	Any device"},
      {V_UP, 29, "Window covering. Up.	S_COVER"},
      {V_DOWN, 30, "Window covering. Down.	S_COVER"},
      {V_STOP, 31, "Window covering. Stop.	S_COVER"},
      {V_IR_SEND, 32, "Send out an IR-command	S_IR"},
      {V_IR_RECEIVE, 33, "This message contains a received IR-command	S_IR"},
      {V_FLOW, 34, "Flow of water (in meter)	S_WATER"},
      {V_VOLUME, 35, "Water volume	S_WATER"},
      {V_LOCK_STATUS, 36, "Set or get lock status. 1=Locked, 0=Unlocked	S_LOCK"},
      {V_LEVEL, 37, "Used for sending level-value	S_DUST, S_AIR_QUALITY, S_SOUND (dB), S_VIBRATION (hz), S_LIGHT_LEVEL (lux)"},
      {V_VOLTAGE, 38, "Voltage level	S_MULTIMETER"},
      {V_CURRENT, 39, "Current level	S_MULTIMETER"},
      {V_RGB, 40, "RGB value transmitted as ASCII hex string (I.e 'ff0000' for red)	S_RGB_LIGHT, S_COLOR_SENSOR"},
      {V_RGBW, 41, "RGBW value transmitted as ASCII hex string (I.e 'ff0000ff' for red + full white)	S_RGBW_LIGHT"},
      {V_ID, 42, "Optional unique sensor id (e.g. OneWire DS1820b ids)	S_TEMP"},
      {V_UNIT_PREFIX, 43, "Allows sensors to send in a string representing the unit prefix to be displayed in GUI. This is not parsed by controller! E.g. cm, m, km, inch.	S_DISTANCE, S_DUST, S_AIR_QUALITY"},
      {V_HVAC_SETPOINT_COOL, 44, "HVAC cold setpoint	S_HVAC"},
      {V_HVAC_SETPOINT_HEAT, 45, "HVAC/Heater setpoint	S_HVAC, S_HEATER"},
      {V_HVAC_FLOW_MODE, 46, "Flow mode for HVAC ('Auto', 'ContinuousOn', 'PeriodicOn')	S_HVAC"},
      {V_TEXT, 47, "Text message to display on LCD or controller device	S_INFO"},
      {V_CUSTOM, 48, "Custom messages used for controller/inter node specific commands, preferably using S_CUSTOM device type.	S_CUSTOM"},
      {V_POSITION, 49, "GPS position and altitude. Payload: latitude;longitude;altitude(m). E.g. '55.722526;13.017972;18'	S_GPS"},
      {V_IR_RECORD, 50, "Record IR codes S_IR for playback	S_IR"},
      {V_PH, 51, "Water PH	S_WATER_QUALITY"},
      {V_ORP, 52, "Water ORP : redox potential in mV	S_WATER_QUALITY"},
      {V_EC, 53, "Water electric conductivity μS/cm (microSiemens/cm)	S_WATER_QUALITY"},
      {V_VAR, 54, "Reactive power: volt-ampere reactive (var)	S_POWER"},
      {V_VA, 55, "Apparent power: volt-ampere (VA)	S_POWER"},
      {V_POWER_FACTOR, 56, "Ratio of real power to apparent power: floating point value in the range [-1,..,1]	S_POWER"},
    ]
  end


  @doc """
  Get a type from the given ID
  """
  @spec variable_type(id) :: variable
  def variable_type(value) do
    value |> _lookup_by_value(variable())
  end


  @doc """
  Get an ID from the given type
  """
  @spec variable_id(variable) :: id
  def variable_id(type) do
    type |> _lookup_by_type(variable())
  end



  # Lookup a type in an array using it's value
  defp _lookup_by_value(id, array) do
    case Enum.find(array, fn {_t, i, _m} -> id == i end) do
      {t, _, _m}  -> t
      _           -> id
    end
  end


  # Lookup an id in an array using it's type
  defp _lookup_by_type(type, array) do
    case Enum.find(array, fn {t, _i, _m} -> type == t end) do
      {_, i, _m}  -> i
      _           -> type
    end
  end


end
