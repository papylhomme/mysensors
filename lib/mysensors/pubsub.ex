defmodule MySensors.PubSub do

  @moduledoc """
  A supervisable PubSub behaviour for events with support for global handler, built on top of `Registry`

  ## Global handlers

  Handlers wishing to receive every events regardless of the dispatching topic need to register to the `:global` topic.
  In case an handler is also registered to a specific topic, the event is dispatched only once.

  ## Behaviour

  Modules using this behaviour include callbacks to start the PubSub as part of a supervision tree,
  and `@registry` is defined as a reference to the PubSub process.

  The following functions are automatically imported:
  - `register/2` to register an handler
  - `unregister/2` to unregister an handler
  - `dispatch_event/3` to dispatch an event to the handlers
  """

  @typedoc "Type of a topic"
  @type topic :: :global | Registry.key

  @typedoc "Type of topics parameters"
  @type topics :: topic | [topic]


  defmacro __using__(_opts) do
    quote do

      import MySensors.PubSub

      @registry __MODULE__

      @doc false
      def child_spec(opts) do
        %{
          id: __MODULE__,
          start: {__MODULE__, :start_link, [Keyword.merge(opts, keys: :duplicate, name: @registry)]},
          type: :worker,
          restart: :permanent,
          shutdown: 500
        }
      end


      @doc false
      def start_link(opts) do
        Registry.start_link(opts)
      end

    end
  end


  @doc """
  Registers an handler to the given `topic`
  """
  @spec register(Registry.registry, topics) :: {:ok, pid} | {:error, any}
  def register(registry, topic) do
    Registry.register(registry, topic, :ok)
  end


  @doc """
  Unregisters an handler from the given `topic`
  """
  @spec unregister(Registry.registry, topics) :: :ok
  def unregister(registry, topic) do
    Registry.unregister(registry, topic)
  end


  @doc """
  Dispatch an `event` to the given `topic`
  """
  @spec dispatch_event(Registry.registry, topic, term) :: :ok
  def dispatch_event(registry, topic, event) do
    Task.start(fn ->
      handlers = _dispatch_to_global_handlers(registry, event)

      Registry.dispatch(registry, topic, fn entries ->
        entries
        |> Enum.reject(fn {pid, _} -> Enum.member?(handlers, pid) end)
        |> Enum.each(fn {pid, _} -> _dispatch(registry, pid, event) end)
      end)
    end)

    :ok
  end


  # Helper to dispatch an event to global handlers
  #
  # This functions returns the list of notified handlers
  defp _dispatch_to_global_handlers(registry, event) do
    Registry.dispatch(registry, :global, fn entries -> Enum.each(entries, fn {pid, _} -> _dispatch(registry, pid, event) end) end)

    Registry.lookup(registry, :global)
    |> Enum.map(fn {pid, _} -> pid end)
  end


  # Helper to send a dispatched message to a process
  defp _dispatch(registry, pid, event) do
    send(pid, {registry, event})
  end

end
