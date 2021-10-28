defmodule Ecto.Adapters.Mnesia.Connection do
  @moduledoc false
  use GenServer

  alias Ecto.Adapters.Mnesia.Config
  alias Ecto.Adapters.Mnesia.Source
  alias Ecto.Adapters.Mnesia.Storage

  @id_seq_table_name :mnesia_id_seq
  @sources_tid Module.concat([__MODULE__, "Sources"])
  @checkout_tid Module.concat([__MODULE__, "Checkout"])

  defmodule State do
    @moduledoc false
    defstruct storage_ref: nil,
              storage_up: false,
              config: nil,
              sources: nil,
              checkout: nil,
              tables: []
  end

  def start_link(config) do
    __MODULE__
    |> GenServer.start_link(config, name: __MODULE__)
    |> case do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      {:error, reason} -> {:error, reason}
    end
  end

  def add_waited_schemas(schemas),
    do: GenServer.cast(__MODULE__, {:wait_for, schemas})

  def checkout(%{timeout: timeout}),
    do: GenServer.call(__MODULE__, :checkout, timeout)

  def source(schema),
    do: GenServer.call(__MODULE__, {:source, schema})

  @impl GenServer
  def init(config) do
    config = Config.ensure_mnesia_config(config)

    sources = :ets.new(@sources_tid, [])
    checkout = :ets.new(@checkout_tid, [:bag])
    state = wait_for_storage(%State{config: config, sources: sources, checkout: checkout})

    {:ok, state}
  end

  @impl GenServer
  def handle_call({:source, params}, _from, s) do
    key =
      case params do
        {_table, _schema, _prefix} = key -> key
        %{schema: schema, source: table, prefix: prefix} -> {table, schema, prefix}
      end

    source =
      case :ets.lookup(s.sources, key) do
        [] -> Source.new(key, :query)
        [source] -> source
      end

    {:reply, source, s}
  end

  def handle_call(:checkout, _from, %State{storage_up: true} = s) do
    {:reply, :ok, s}
  end

  def handle_call(:checkout, from, %State{checkout: checkout} = s) do
    :ets.insert(checkout, {:checkout, from})
    {:noreply, s}
  end

  @impl GenServer
  def handle_cast({:wait_for, schemas}, %State{} = s) do
    tables =
      schemas
      |> Enum.reduce([], fn schema, acc ->
        case apply(schema, :__schema__, [:source]) do
          nil -> acc
          source -> [source | acc]
        end
      end)

    s = wait_for_storage(%{s | tables: s.tables ++ tables})
    {:noreply, s}
  end

  @impl GenServer
  def handle_info({:storage_up, ref}, %State{storage_ref: ref, checkout: checkout} = s) do
    checkout
    |> :ets.lookup(:checkout)
    |> Enum.each(fn {:checkout, from} ->
      GenServer.reply(from, :ok)
    end)

    :ets.delete_all_objects(checkout)

    {:noreply, %{s | storage_ref: nil, storage_up: true}}
  end

  @impl GenServer
  def terminate(_reason, state) do
    try do
      :dets.sync(@id_seq_table_name)
      state
    rescue
      e -> e
    end
  end

  def id_seq_table_name, do: @id_seq_table_name

  def id_seq(source), do: {@id_seq_table_name, source}

  defp wait_for_storage(%State{storage_ref: nil} = s) do
    conn = self()
    ref = make_ref()

    spawn(fn -> wait_for_storage_task(s.tables, conn, ref) end)

    %{s | storage_ref: ref, storage_up: false}
  end

  defp wait_for_storage(%State{storage_ref: ref} = s) do
    Task.shutdown(ref)
    wait_for_storage(%{s | storage_ref: nil})
  end

  defp wait_for_storage_task(tables, conn, ref) do
    :ok = Storage.wait_for_tables(tables, :infinity)
    send(conn, {:storage_up, ref})
  end
end
