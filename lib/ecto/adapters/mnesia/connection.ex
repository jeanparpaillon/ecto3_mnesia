defmodule Ecto.Adapters.Mnesia.Connection do
  @moduledoc false
  use GenServer

  alias Ecto.Adapters.Mnesia
  alias Ecto.Adapters.Mnesia.Connection
  alias Ecto.Adapters.Mnesia.Constraint
  alias Ecto.Adapters.Mnesia.Source

  @id_seq_table_name :mnesia_id_seq
  @sources_tid Module.concat([__MODULE__, :Sources])

  def start_link(config) do
    Connection
    |> GenServer.start_link([config], name: __MODULE__)
    |> case do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      {:error, reason} -> {:error, reason}
    end
  end

  def source(schema),
    do: GenServer.call(__MODULE__, {:source, schema})

  @impl GenServer
  def init(config) do
    sources = :ets.new(@sources_tid, [])
    {:ok, %{config: config, sources: sources}}
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

  def all(type, %Ecto.Query{} = query) do
    Mnesia.Query.from_ecto_query(type, query)
  end

  def ensure_id_seq_table(nil) do
    ensure_id_seq_table([node()])
  end

  def ensure_id_seq_table(nodes) when is_list(nodes) do
    case :mnesia.create_table(@id_seq_table_name,
           disc_copies: nodes,
           attributes: [:id, :seq],
           type: :set,
           storage_properties: [dets: [auto_save: 5_000]],
           load_order: 100
         ) do
      {:atomic, :ok} ->
        :mnesia.wait_for_tables([@id_seq_table_name], 1_000)

      {:aborted, {:already_exists, @id_seq_table_name}} ->
        :ok
    end
  end

  def ensure_constraints_table(nil) do
    ensure_constraints_table([node()])
  end

  def ensure_constraints_table(nodes) when is_list(nodes) do
    Constraint.ensure_table(nodes)
  end
end
