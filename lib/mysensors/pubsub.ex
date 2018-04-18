defmodule MySensors.PubSub do
  alias Phoenix.PubSub


  defmacro __using__(_) do
    quote do
      import MySensors.PubSub
    end
  end


  @doc """
  Defines simple helpers for a topic
  """
  defmacro topic_helpers(bus, topic, name) do
    quote do

      @doc """
      Subscribe the caller to the topic

      Subscribers will receive messages as `{:mysensors, topic, message}` tuples.
      """
      @spec unquote(:"subscribe_#{name}")() :: :ok | {:error, term}
      def unquote(:"subscribe_#{name}")() do
        PubSub.subscribe(unquote(bus), unquote(topic) |> Atom.to_string)
      end

      @doc """
      Unsubscribe the caller from the topic
      """
      @spec unquote(:"unsubscribe_#{name}")() :: :ok | {:error, term}
      def unquote(:"unsubscribe_#{name}")() do
        PubSub.unsubscribe(unquote(bus), unquote(topic) |> Atom.to_string)
      end

      @doc """
      Broadcast a message to the topic
      """
      @spec unquote(:"broadcast_#{name}")(any) :: :ok | {:error, term}
      def unquote(:"broadcast_#{name}")(message) do
        PubSub.broadcast(unquote(bus), unquote(topic) |> Atom.to_string, {:mysensors, unquote(topic), message})
      end

    end
  end

end
