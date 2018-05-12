defmodule MySensors.PubSub do
  alias Phoenix.PubSub


  defmacro __using__(_) do
    quote do
      import MySensors.PubSub
    end
  end


  def topic_name(topic_name, params) do
    case topic_name do
      name when is_atom(name) -> name |> Atom.to_string
      f when is_function(f)   -> f.(params)
    end
  end


  @doc """
  Defines simple helpers for a topic
  """
  defmacro topic_helpers(bus, topic) do
    quote do

      @doc """
      Subscribe the caller to the topic

      Subscribers will receive messages as `{:mysensors, topic, message}` tuples.
      """
      @spec unquote(:"subscribe_#{topic}")() :: :ok | {:error, term}
      def unquote(:"subscribe_#{topic}")() do
        PubSub.subscribe(unquote(bus), unquote(topic) |> Atom.to_string)
      end

      @doc """
      Unsubscribe the caller from the topic
      """
      @spec unquote(:"unsubscribe_#{topic}")() :: :ok | {:error, term}
      def unquote(:"unsubscribe_#{topic}")() do
        PubSub.unsubscribe(unquote(bus), unquote(topic) |> Atom.to_string)
      end

      @doc """
      Broadcast a message to the topic
      """
      @spec unquote(:"broadcast_#{topic}")(any) :: :ok | {:error, term}
      def unquote(:"broadcast_#{topic}")(message) do
        PubSub.broadcast(unquote(bus), unquote(topic |> Atom.to_string), {:mysensors, unquote(topic), message})
      end

    end
  end


  defmacro topic_helpers(bus, topic, topic_name) do
    quote do

      @doc """
      Subscribe the caller to the topic

      Subscribers will receive messages as `{:mysensors, topic, message}` tuples.
      """
      @spec unquote(:"subscribe_#{topic}")(any) :: :ok | {:error, term}
      def unquote(:"subscribe_#{topic}")(params) do
        name = topic_name(unquote(topic_name), params)
        PubSub.subscribe(unquote(bus), name)
        name
      end

      @doc """
      Unsubscribe the caller from the topic
      """
      @spec unquote(:"unsubscribe_#{topic}")(any) :: :ok | {:error, term}
      def unquote(:"unsubscribe_#{topic}")(params) do
        PubSub.unsubscribe(unquote(bus), topic_name(unquote(topic_name), params))
      end

      @doc """
      Broadcast a message to the topic
      """
      @spec unquote(:"broadcast_#{topic}")(any, any) :: :ok | {:error, term}
      def unquote(:"broadcast_#{topic}")(params, message) do
        name = topic_name(unquote(topic_name), params)
        PubSub.broadcast(unquote(bus), name, {:mysensors, unquote(topic), message})
      end

    end
  end


end
