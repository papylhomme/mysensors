defmodule MySensors do

  @moduledoc """
  MySensors Application
  """

  use Application


  @doc """
  Start the application
  """
  def start(_type, _args) do
    MySensors.Supervisor.start_link
  end

end

