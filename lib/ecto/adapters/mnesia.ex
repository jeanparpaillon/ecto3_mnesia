defmodule Ecto.Adapters.Mnesia do
  @moduledoc """
  # Ecto Mnesia Adapter
  This adapter brings the strength of Ecto providing validation, and persistance layer to interact to Mnesia databases.

  Mnesia is Distributed Database Management System shipped with Erlang runtime. Be aware of strengths and weaknesses listed in [erlang documentation](https://erlang.org/doc/man/mnesia.html) before thinking about using it.


  ## What works
  1. Queries
  - [x] Basic all queries
  - [x] Select queries
  - [x] Simple where queries
  - [x] and/or/in in where clauses
  - [x] Bindings
  - [ ] Fragments
  - [x] Limit/Offset queries
  - [x] Sort by one field
  - [ ] Sort by multiple fields
  - [x] One level joins
  - [ ] Deeper joins

  2. Writing operations
  - [x] insert/insert_all
  - [x] update/update_all
  - [x] delete/delete_all
  - [x] Auto incremented ids
  - [x] Binary ids

  Note: supports only on_conflict: :raise/:update_all

  3. Associations
  - [x] has_one associations
  - [x] has_many associations
  - [x] belongs_to associations
  - [ ] many_to_many associations

  4. Transactions
  - [x] Create transactions
  - [x] Rollback transactions

  ## Instalation
  You can include ecto3_mnesia in your dependencies as follow:
  ```
    defp deps do
      ...
      {:ecto3_mnesia, "~> 0.1.0"}, # not released yet
      ...
    end
  ```
  Then configure your application repository to use Mnesia adapter as follow:
  ```
  # ./lib/my_app/repo.ex
  defmodule MyApp.Repo do
    use Ecto.Repo,
      otp_app: :my_app,
      adapter: Ecto.Adapters.Mnesia
  end
  ```

  ## Migrations
  Migrations are not supported yet, you can use mnesia abilities to create tables in a script.
  ```
  # ./priv/repo/mnesia_migration.exs
  IO.inspect :mnesia.create_table(:table_name, [
    disc_copies: [node()],
    record_name: MyApp.Context.Schema,
    attributes: [:id, :field, :updated_at, :inserted_at],
    type: :set
  ])
  ```
  Then run the script with mix `mix run ./priv/repo/mnesia_migration.exs`
  Notice that the table before MUST be defined according to the corresponding schema
  ```
  defmodule MyApp.Context.Schema do
    ...
    schema "table_name" do
      field :field, :string

      timestamps()
    end
    ...
  end
  ```
  """
  @behaviour Ecto.Adapter
  @behaviour Ecto.Adapter.Queryable
  @behaviour Ecto.Adapter.Schema
  @behaviour Ecto.Adapter.Storage
  @behaviour Ecto.Adapter.Transaction

  case Application.load(:ecto) do
    :ok -> :ok
    {:error, {:already_loaded, _}} -> :ok
  end

  @ecto_vsn :ecto |> Application.spec(:vsn) |> to_string()

  import Ecto.Query

  alias Ecto.Adapters.Mnesia
  alias Ecto.Adapters.Mnesia.Connection
  alias Ecto.Adapters.Mnesia.Record
  alias Ecto.Adapters.Mnesia.Source

  require Logger

  @impl Ecto.Adapter
  defmacro __before_compile__(_env), do: true

  @impl Ecto.Adapter
  def checkout(_adapter_meta, _config, function) do
    function.()
  end

  @impl Ecto.Adapter
  def checked_out?(_adapter_meta), do: true

  @impl Ecto.Adapter
  def dumpers(_, type), do: [type]

  @impl Ecto.Adapter
  def ensure_all_started(_config, _type) do
    {:ok, _} = Application.ensure_all_started(:mnesia)
    {:ok, []}
  end

  @impl Ecto.Adapter
  def init(config \\ []) do
    {:ok, Connection.child_spec(config), %{}}
  end

  @impl Ecto.Adapter
  def loaders(_primitive, type), do: [type]

  @impl Ecto.Adapter.Queryable
  def prepare(type, query) do
    {:nocache, Connection.all(type, query)}
  end

  @impl Ecto.Adapter.Queryable
  def execute(
        adapter_meta,
        _query_meta,
        {:nocache,
         %Mnesia.Query{
           type: :all,
           sources: sources,
           query: query,
           sort: sort,
           answers: answers
         }},
        params,
        _opts
      ) do
    context = [params: params]

    case :timer.tc(&mnesia_transaction_wrapper/2, [
           adapter_meta,
           fn ->
             query.(params)
             |> sort.()
             |> answers.(context)
             |> Enum.map(&Tuple.to_list(&1))
           end
         ]) do
      {time, {:atomic, result}} ->
        Logger.debug("QUERY OK sources=#{inspect(sources)} type=all db=#{time}µs")

        {length(result), result}

      {time, {:aborted, error}} ->
        Logger.debug(
          "QUERY ERROR sources=#{inspect(sources)} type=all db=#{time}µs #{inspect(error)}"
        )

        {0, []}
    end
  end

  def execute(
        adapter_meta,
        _query_meta,
        {:nocache,
         %Mnesia.Query{
           type: :update_all,
           sources: [%Source{} = source | _] = sources,
           query: query,
           answers: answers,
           new_record: new_record
         }},
        params,
        _opts
      ) do
    answers_context = [params: params]

    case :timer.tc(&mnesia_transaction_wrapper/2, [
           adapter_meta,
           fn ->
             query.(params)
             |> answers.(answers_context)
             |> Enum.map(&new_record.(&1, params))
             |> Enum.map(fn record ->
               with :ok <- :mnesia.write(source.table, record, :write) do
                 Record.to_schema(record, source)
               end
             end)
           end
         ]) do
      {time, {:atomic, result}} ->
        Logger.debug(
          "QUERY OK sources=#{sources |> Enum.map(& &1.table) |> Enum.join(",")} type=update_all db=#{
            time
          }µs"
        )

        {length(result), result}

      {time, {:aborted, error}} ->
        Logger.debug(
          "QUERY ERROR sources=#{sources |> Enum.map(& &1.table) |> Enum.join(",")} type=update_all db=#{
            time
          }µs #{inspect(error)}"
        )

        {0, nil}
    end
  end

  def execute(
        adapter_meta,
        _query_meta,
        {:nocache,
         %Mnesia.Query{
           original: original,
           type: :delete_all,
           sources: [%Source{} = source | _] = sources,
           query: query,
           answers: answers
         }},
        params,
        _opts
      ) do
    context = [params: params]

    case :timer.tc(&mnesia_transaction_wrapper/2, [
           adapter_meta,
           fn ->
             query.(params)
             |> answers.(context)
             |> Enum.map(fn tuple ->
               # Works only if query selects id at first, see: https://gitlab.com/patatoid/ecto3_mnesia/-/issues/15
               id = elem(tuple, 0)
               :mnesia.delete(source.table, id, :write)
               Tuple.to_list(tuple)
             end)
           end
         ]) do
      {time, {:atomic, records}} ->
        Logger.debug(
          "QUERY OK sources=#{sources |> Enum.map(& &1.table) |> Enum.join(",")} type=delete_all db=#{
            time
          }µs"
        )

        result =
          case original.select do
            nil -> nil
            %Ecto.Query.SelectExpr{} -> records
          end

        {length(records), result}

      {time, {:aborted, error}} ->
        Logger.debug(
          "QUERY ERROR sources=#{sources |> Enum.map(& &1.table) |> Enum.join(",")} type=delete_all db=#{
            time
          }µs #{inspect(error)}"
        )

        {0, nil}
    end
  end

  @impl Ecto.Adapter.Queryable
  def stream(
        adapter_meta,
        _query_meta,
        {:nocache, %Mnesia.Query{query: query, answers: answers}},
        params,
        _opts
      ) do
    case mnesia_transaction_wrapper(
           adapter_meta,
           fn ->
             query.(params)
             |> answers.()
             |> Enum.map(&Tuple.to_list(&1))
           end
         ) do
      {:atomic, result} ->
        result

      _ ->
        []
    end
  end

  @impl Ecto.Adapter.Schema
  def autogenerate(:id), do: nil

  def autogenerate(:binary_id), do: Ecto.UUID.generate()

  @doc """
  Increment autogenerated id and return new value for given source and field
  """
  @spec next_id(atom(), atom()) :: integer()
  def next_id(table_name, key) do
    :mnesia.dirty_update_counter(Connection.id_seq({table_name, key}), 1)
  end

  @impl Ecto.Adapter.Schema
  def insert(adapter_meta, schema_meta, params, on_conflict, returning, _opts) do
    source = Source.new(schema_meta)

    case :timer.tc(&mnesia_transaction_wrapper/2, [
           adapter_meta,
           fn -> upsert(source, params, on_conflict, adapter_meta) end
         ]) do
      {time, {:atomic, [record]}} ->
        result = Record.select(record, returning, source)
        Logger.debug("QUERY OK source=#{inspect(schema_meta.source)} type=insert db=#{time}µs")
        {:ok, result}

      {time, {:aborted, error}} ->
        Logger.debug(
          "QUERY ERROR source=#{inspect(schema_meta.source)} type=insert db=#{time}µs #{
            inspect(error)
          }"
        )

        {:invalid, error}
    end
  end

  if Version.compare(@ecto_vsn, "3.6.0") in [:eq, :gt] do
    @impl Ecto.Adapter.Schema
    def insert_all(adapter_meta, schema, header, records, on_conflict, returning, [], opts),
      do: do_insert_all(adapter_meta, schema, header, records, on_conflict, returning, opts)

    @impl Ecto.Adapter.Schema
    def insert_all(_, _, _, _, _, _, _placeholders, _),
      do: raise(ArgumentError, ":placeholders is not supported by mnesia")
  else
    @impl Ecto.Adapter.Schema
    def insert_all(adapter_meta, schema, header, records, on_conflict, returning, opts),
      do: do_insert_all(adapter_meta, schema, header, records, on_conflict, returning, opts)
  end

  defp do_insert_all(adapter_meta, schema_meta, _header, records, on_conflict, returning, _opts) do
    source = Source.new(schema_meta)

    case :timer.tc(&mnesia_transaction_wrapper/2, [
           adapter_meta,
           fn ->
             Enum.map(records, fn params ->
               upsert(source, params, on_conflict, adapter_meta)
             end)
           end
         ]) do
      {time, {:atomic, created_records}} ->
        result =
          Enum.map(created_records, fn [record] ->
            record
            |> Record.select(returning, source)
            |> Enum.map(&elem(&1, 1))
          end)

        Logger.debug(
          "QUERY OK source=#{inspect(schema_meta.source)} type=insert_all db=#{time}µs"
        )

        {length(result), result}

      {time, {:aborted, error}} ->
        Logger.debug(
          "QUERY ERROR source=#{inspect(schema_meta.source)} type=insert_all db=#{time}µs #{
            inspect(error)
          }"
        )

        {0, nil}
    end
  end

  @impl Ecto.Adapter.Schema
  def update(adapter_meta, schema_meta, params, filters, returning, _opts) do
    source = Source.new(schema_meta)
    answers_context = [params: params]
    query = Mnesia.Qlc.query(:all, [], [source]).(filters)

    with {selectTime, {:atomic, [attributes]}} <-
           :timer.tc(&mnesia_transaction_wrapper/2, [
             adapter_meta,
             fn ->
               query.(params) |> Mnesia.Qlc.answers(nil, nil).(answers_context)
             end
           ]),
         {updateTime, {:atomic, update}} <-
           :timer.tc(&mnesia_transaction_wrapper/2, [
             adapter_meta,
             fn ->
               updated =
                 attributes
                 |> Record.new(source)
                 |> Record.update(params, source)

               with :ok <- :mnesia.write(source.table, updated, :write) do
                 updated
               end
             end
           ]) do
      result = Record.select(update, returning, source)

      Logger.debug(
        "QUERY OK source=#{inspect(source.table)} type=update db=#{selectTime + updateTime}µs"
      )

      {:ok, result}
    else
      {time, {:atomic, []}} ->
        Logger.debug(
          "QUERY ERROR source=#{inspect(source.table)} type=update db=#{time}µs \"No results\""
        )

        {:error, :stale}

      {time, {:aborted, error}} ->
        Logger.debug(
          "QUERY ERROR source=#{inspect(source.table)} type=update db=#{time}µs #{inspect(error)}"
        )

        {:invalid, [mnesia: "#{inspect(error)}"]}
    end
  end

  @impl Ecto.Adapter.Schema
  def delete(adapter_meta, schema_meta, filters, _opts) do
    source = Source.new(schema_meta)
    query = Mnesia.Qlc.query(:all, [], [source]).(filters)

    with {selectTime, {:atomic, [[id | _t]]}} <-
           :timer.tc(&mnesia_transaction_wrapper/2, [
             adapter_meta,
             fn ->
               query.([])
               |> Mnesia.Qlc.answers(nil, nil).(params: [])
               |> Enum.map(&Tuple.to_list(&1))
             end
           ]),
         {deleteTime, {:atomic, :ok}} <-
           :timer.tc(:mnesia, :transaction, [
             fn ->
               :mnesia.delete(source.table, id, :write)
             end
           ]) do
      Logger.debug(
        "QUERY OK source=#{inspect(source.table)} type=delete db=#{selectTime + deleteTime}µs"
      )

      {:ok, []}
    else
      {time, {:atomic, []}} ->
        Logger.debug(
          "QUERY ERROR source=#{inspect(source.table)} type=delete db=#{time}µs \"No results\""
        )

        {:error, :stale}

      {time, {:aborted, error}} ->
        Logger.debug(
          "QUERY ERROR source=#{inspect(source.table)} type=delete db=#{time}µs #{inspect(error)}"
        )

        {:invalid, [mnesia: "#{inspect(error)}"]}
    end
  end

  @impl Ecto.Adapter.Transaction
  def in_transaction?(_adapter_meta), do: :mnesia.is_transaction()

  @impl Ecto.Adapter.Transaction
  def transaction(_adapter_meta, _options, function) do
    case :mnesia.transaction(fn ->
           function.()
         end) do
      {:atomic, result} -> {:ok, result}
      {:aborted, reason} -> {:error, reason}
    end
  end

  @impl Ecto.Adapter.Transaction
  def rollback(_adapter_meta, value) do
    if :mnesia.is_transaction() do
      throw(:mnesia.abort(value))
    else
      raise "not inside transaction"
    end
  end

  @impl Ecto.Adapter.Storage
  def storage_up(options) do
    :mnesia.stop()

    case :mnesia.create_schema(options[:nodes] || [node()]) do
      :ok ->
        :mnesia.start()

      {:error, {_, {:already_exists, _}}} ->
        with :ok <- :mnesia.start() do
          {:error, :already_up}
        end
    end
  end

  @impl Ecto.Adapter.Storage
  def storage_down(options) do
    :mnesia.stop()

    case :mnesia.delete_schema(options[:nodes] || [node()]) do
      :ok ->
        :mnesia.start()
    end
  end

  @impl Ecto.Adapter.Storage
  def storage_status(_options) do
    path = List.to_string(:mnesia.system_info(:directory)) <> "/schema.DAT"

    case File.exists?(path) do
      true -> :up
      false -> :down
    end
  end

  # Wraps a function and decides if executing it as part of an already existant transaction
  # or wrapping it into a :mnesia.transaction block
  defp mnesia_transaction_wrapper(meta, fun) do
    case in_transaction?(meta) do
      true ->
        # mnesia atomic operations (write, etc) always end with :ok or interrupts with exceptions
        try do
          {:atomic, fun.()}
        catch
          :exit, {:aborted, reason} ->
            {:aborted, reason}

          :exit, reason ->
            {:aborted, reason}
        end

      false ->
        :mnesia.transaction(fun)
    end
  end

  defp upsert(source, params, {:raise, [], []}, adapter_meta) do
    case conflict?(params, source, adapter_meta) do
      nil ->
        do_insert(params, source)

      {_rec, constraints} ->
        :mnesia.abort(constraints)
    end
  end

  defp upsert(source, params, {:nothing, [], []}, adapter_meta) do
    case conflict?(params, source, adapter_meta) do
      nil ->
        do_insert(params, source)

      {_rec, _constraints} ->
        [Record.new(params, source)]
    end
  end

  defp upsert(source, params, {fields, [], []}, adapter_meta) when is_list(fields) do
    all_fields = Source.fields(source)

    case all_fields -- fields do
      [] ->
        # ie replace_all
        do_insert(params, source)

      _ ->
        case conflict?(params, source, adapter_meta) do
          nil ->
            do_insert(params, source)

          {conflict, _constraints} ->
            updated = conflict |> Record.new(source) |> Record.update(params, source, fields)
            with :ok <- :mnesia.write(source.table, updated, :write), do: [updated]
        end
    end
  end

  defp do_insert(params, source) do
    record =
      params
      |> Record.gen_id(source)
      |> Record.new(source)

    with :ok <- :mnesia.write(source.table, record, :write), do: [record]
  end

  defp conflict?(params, source, %{repo: repo}) do
    source
    |> Source.uniques(params)
    |> case do
      [] ->
        nil

      uniques ->
        source.schema
        |> from()
        |> where(^uniques)
        |> repo.one()
        |> case do
          nil ->
            nil

          conflict ->
            constraints =
              uniques
              |> Enum.reduce([], fn {key, value}, acc ->
                case Map.get(conflict, key) do
                  ^value -> [{:unique, "#{source.table}_#{key}_index"} | acc]
                  _ -> acc
                end
              end)

            {conflict, constraints}
        end
    end
  end
end
