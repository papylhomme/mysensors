alias MySensors.Gateway, as: GW
alias MySensors.SensorEvents, as: SE
alias MySensors.NodeEvents, as: NE

defmodule H do

  def obs do
    :observer.start
  end

  def nodes() do
    MySensors.NodeManager.nodes
  end
  
  
  def sensors(node) do
    MySensors.Node.sensors(node.pid)
  end

end
