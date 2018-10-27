defmodule MySensors.PubSub do

  defmacro __using__(_) do
    quote do
      import MySensors.PubSub
    end
  end


  def topic_name(topic_name, params \\ nil) do
    case topic_name do
      name when is_atom(name) -> name |> Atom.to_string
      name when is_binary(name) -> name
      f when is_function(f)   -> f.(params)
    end
  end


  @doc """
  Defines simple helpers for a topic
  """
  defmacro topic_helpers(bus, topic) do
    quote do
      @bus unquote(bus)
      @topic unquote(topic)

      @doc """
      Subscribe the caller to the topic

      Subscribers will receive messages as `{:mysensors, topic, message}` tuples.
      """
      @spec unquote(:"subscribe_#{topic}")() :: :ok | {:error, term}
      def unquote(:"subscribe_#{topic}")(), do: @bus.subscribe(MySensors.PubSub.topic_name(@topic))

      @doc "Unsubscribe the caller from the topic"
      @spec unquote(:"unsubscribe_#{topic}")() :: :ok | {:error, term}
      def unquote(:"unsubscribe_#{topic}")(), do: @bus.unsubscribe(MySensors.PubSub.topic_name(@topic))

      @doc "Broadcast a message to the topic"
      @spec unquote(:"broadcast_#{topic}")(any) :: :ok | {:error, term}
      def unquote(:"broadcast_#{topic}")(message), do: @bus.broadcast(MySensors.PubSub.topic_name(@topic), {:mysensors, @topic, message})

    end
  end


  defmacro topic_helpers(bus, topic, topic_name) do
    quote do
      @topic unquote(topic)
      @bus unquote(bus)

      @doc "Returns a computed `#{unquote(topic)}` topic name"
      @spec unquote(:"topic_#{topic}")(any) :: String.t
      def unquote(:"topic_#{topic}")(params) do
        MySensors.PubSub.topic_name(unquote(topic_name), params)
      end

      @doc """
      Subscribe the caller to the `#{unquote(topic)}` topic

      Subscribers will receive messages as `{:mysensors, #{inspect unquote(topic)}, message}` tuples.
      """
      @spec unquote(:"subscribe_#{topic}")(any) :: :ok | {:error, term}
      def unquote(:"subscribe_#{topic}")(params), do: @bus.subscribe(MySensors.PubSub.topic_name(unquote(topic_name), params))

      @doc "Unsubscribe the caller from the `#{unquote(topic)}` topic"
      @spec unquote(:"unsubscribe_#{topic}")(any) :: :ok | {:error, term}
      def unquote(:"unsubscribe_#{topic}")(params), do: @bus.unsubscribe(MySensors.PubSub.topic_name(unquote(topic_name), params))

      @doc "Broadcast a message to the `#{unquote(topic)}` topic"
      @spec unquote(:"broadcast_#{topic}")(any, any) :: :ok | {:error, term}
      def unquote(:"broadcast_#{topic}")(params, message), do: @bus.broadcast(MySensors.PubSub.topic_name(unquote(topic_name), params), {:mysensors, unquote(topic), message})

    end
  end


  defmacro topic_helpers(bus, topic, topic_name, global_topic) do
    quote do
      @bus unquote(bus)

      @doc """
      Subscribe the caller to the global topic

      Subscribers will receive messages as `{:mysensors, topic, message}` tuples.
      """
      @spec unquote(:"subscribe_#{global_topic}")() :: :ok | {:error, term}
      def unquote(:"subscribe_#{global_topic}")(), do: @bus.subscribe(MySensors.PubSub.topic_name(unquote(global_topic)))


      @doc """
      Subscribe the caller to the topic

      Subscribers will receive messages as `{:mysensors, topic, message}` tuples.
      """
      @spec unquote(:"subscribe_#{topic}")(any) :: :ok | {:error, term}
      def unquote(:"subscribe_#{topic}")(params), do: @bus.subscribe(MySensors.PubSub.topic_name(unquote(topic_name), params))


      @doc "Unsubscribe the caller from the global topic"
      @spec unquote(:"unsubscribe_#{global_topic}")() :: :ok | {:error, term}
      def unquote(:"unsubscribe_#{global_topic}")(), do: @bus.unsubscribe(MySensors.PubSub.topic_name(unquote(global_topic)))

      @doc "Unsubscribe the caller from the topic"
      @spec unquote(:"unsubscribe_#{topic}")(any) :: :ok | {:error, term}
      def unquote(:"unsubscribe_#{topic}")(params), do: @bus.unsubscribe(MySensors.PubSub.topic_name(unquote(topic_name), params))

      @doc "Broadcast a message to the global topic"
      @spec unquote(:"broadcast_#{topic}")(any, any) :: :ok | {:error, term}
      def unquote(:"broadcast_#{topic}")(message), do: @bus.broadcast(MySensors.PubSub.topic_name(unquote(global_topic)), {:mysensors, unquote(topic), message})

      @doc "Broadcast a message to the topic"
      @spec unquote(:"broadcast_#{topic}")(any, any) :: :ok | {:error, term}
      def unquote(:"broadcast_#{topic}")(params, message) do
        name = MySensors.PubSub.topic_name(unquote(topic_name), params)
        @bus.broadcast(name, {:mysensors, unquote(topic), message})

        name = MySensors.PubSub.topic_name(unquote(global_topic))
        @bus.broadcast(name, {:mysensors, unquote(topic), message})
      end

    end
  end

end
