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

  alias Ecto.Adapters.Mnesia
  alias Ecto.Adapters.Mnesia.Connection
  alias Ecto.Adapters.Mnesia.Record

  require Logger

  @impl Ecto.Adapter
  defmacro __before_compile__(_env), do: true

  @impl Ecto.Adapter
  def checkout(_adapter_meta, _config, function) do
    function.()
  end

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
           sources: sources,
           query: query,
           answers: answers,
           new_record: new_record
         }},
        params,
        _opts
      ) do
    {table_name, schema} = Enum.at(sources, 0)
    answers_context = [params: params]

    record_context = %{
      table_name: table_name,
      schema_meta: %{schema: schema}
    }

    case :timer.tc(&mnesia_transaction_wrapper/2, [
           adapter_meta,
           fn ->
             query.(params)
             |> answers.(answers_context)
             |> Enum.map(&Tuple.to_list(&1))
             |> Enum.map(fn record -> new_record.(record, params) end)
             |> Enum.map(fn record ->
               with :ok <- :mnesia.write(table_name, record, :write) do
                 Record.to_schema(record, record_context)
               end
             end)
           end
         ]) do
      {time, {:atomic, result}} ->
        Logger.debug("QUERY OK sources=#{inspect(sources)} type=update_all db=#{time}µs")

        {length(result), result}

      {time, {:aborted, error}} ->
        Logger.debug(
          "QUERY ERROR sources=#{inspect(sources)} type=update_all db=#{time}µs #{inspect(error)}"
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
           sources: sources,
           query: query,
           answers: answers
         }},
        params,
        _opts
      ) do
    {table_name, _schema} = Enum.at(sources, 0)
    context = [params: params]

    case :timer.tc(&mnesia_transaction_wrapper/2, [
           adapter_meta,
           fn ->
             query.(params)
             |> answers.(context)
             |> Enum.map(&Tuple.to_list(&1))
             |> Enum.map(fn record ->
               :mnesia.delete(table_name, List.first(record), :write)
               record
             end)
           end
         ]) do
      {time, {:atomic, records}} ->
        Logger.debug("QUERY OK sources=#{inspect(sources)} type=delete_all db=#{time}µs")

        result =
          case original.select do
            nil -> nil
            %Ecto.Query.SelectExpr{} -> records
          end

        {length(records), result}

      {time, {:aborted, error}} ->
        Logger.debug(
          "QUERY ERROR sources=#{inspect(sources)} type=delete_all db=#{time}µs #{inspect(error)}"
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
  Returns autogenerated id for given source
  """
  def autogenerate({source, :id}) do
    :mnesia.dirty_update_counter(Connection.id_seq(source), 1)
  end

  def autogenerate({_source, :binary_id}), do: Ecto.UUID.generate()

  @doc """
  Returns sequence tuple for given schema
  """
  def seq_id(schema, seq) do
    key = schema |> apply(:__schema__, [:source]) |> String.to_atom()
    {Connection.id_seq_table_name(), key, seq}
  end

  @impl Ecto.Adapter.Schema
  def insert(adapter_meta, schema_meta, params, on_conflict, returning, _opts) do
    table_name = String.to_atom(schema_meta.source)

    context = %{
      table_name: table_name,
      schema_meta: schema_meta,
      adapter_meta: adapter_meta
    }

    case :timer.tc(&mnesia_transaction_wrapper/2, [
           adapter_meta,
           fn -> upsert(context, params, on_conflict) end
         ]) do
      {time, {:atomic, [record]}} ->
        result = Record.select(record, returning, context)
        Logger.debug("QUERY OK source=#{inspect(schema_meta.source)} type=insert db=#{time}µs")
        {:ok, result}

      {time, {:aborted, error}} ->
        Logger.debug(
          "QUERY ERROR source=#{inspect(schema_meta.source)} type=insert db=#{time}µs #{
            inspect(error)
          }"
        )

        {:invalid, [mnesia: inspect(error)]}
    end
  end

  @impl Ecto.Adapter.Schema
  if Version.compare(@ecto_vsn, "3.6.0") in [:eq, :gt] do
    def insert_all(
          adapter_meta,
          schema,
          header,
          records,
          on_conflict,
          returning,
          _placeholders,
          opts
        ),
        do: insert_all(adapter_meta, schema, header, records, on_conflict, returning, opts)
  end

  def insert_all(
        adapter_meta,
        schema_meta,
        _header,
        records,
        on_conflict,
        returning,
        _opts
      ) do
    table_name = String.to_atom(schema_meta.source)

    context = %{
      table_name: table_name,
      schema_meta: schema_meta,
      adapter_meta: adapter_meta
    }

    case :timer.tc(&mnesia_transaction_wrapper/2, [
           adapter_meta,
           fn ->
             Enum.map(records, fn params ->
               upsert(context, params, on_conflict)
             end)
           end
         ]) do
      {time, {:atomic, created_records}} ->
        result =
          Enum.map(created_records, fn [record] ->
            record
            |> Record.select(returning, context)
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
  def update(
        adapter_meta,
        %{schema: schema, source: source} = schema_meta,
        params,
        filters,
        returning,
        _opts
      ) do
    table_name = String.to_atom(source)
    source = {table_name, schema}

    answers_context = [params: params]

    record_context = %{
      table_name: table_name,
      schema_meta: schema_meta,
      adapter_meta: adapter_meta
    }

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
               update =
                 List.zip([schema.__schema__(:fields), attributes])
                 |> Record.update(params, record_context)
                 |> Record.to_record(record_context)

               with :ok <- :mnesia.write(table_name, update, :write) do
                 update
               end
             end
           ]) do
      result = Record.select(update, returning, record_context)

      Logger.debug(
        "QUERY OK source=#{inspect(source)} type=update db=#{selectTime + updateTime}µs"
      )

      {:ok, result}
    else
      {time, {:atomic, []}} ->
        Logger.debug(
          "QUERY ERROR source=#{inspect(source)} type=update db=#{time}µs \"No results\""
        )

        {:error, :stale}

      {time, {:aborted, error}} ->
        Logger.debug(
          "QUERY ERROR source=#{inspect(source)} type=update db=#{time}µs #{inspect(error)}"
        )

        {:invalid, [mnesia: "#{inspect(error)}"]}
    end
  end

  @impl Ecto.Adapter.Schema
  def delete(
        adapter_meta,
        %{schema: schema, source: source},
        filters,
        _opts
      ) do
    table_name = String.to_atom(source)
    source = {table_name, schema}

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
               :mnesia.delete(table_name, id, :write)
             end
           ]) do
      Logger.debug(
        "QUERY OK source=#{inspect(source)} type=delete db=#{selectTime + deleteTime}µs"
      )

      {:ok, []}
    else
      {time, {:atomic, []}} ->
        Logger.debug(
          "QUERY ERROR source=#{inspect(source)} type=delete db=#{time}µs \"No results\""
        )

        {:error, :stale}

      {time, {:aborted, error}} ->
        Logger.debug(
          "QUERY ERROR source=#{inspect(source)} type=delete db=#{time}µs #{inspect(error)}"
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
    throw(:mnesia.abort(value))
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
        {:atomic, fun.()}

      false ->
        :mnesia.transaction(fun)
    end
  end

  defp upsert(context, params, {:raise, [], []}) do
    case conflict?(params, context) do
      nil ->
        do_insert(params, context)

      _conflict ->
        :mnesia.abort("Record already exists")
    end
  end

  defp upsert(context, params, {:nothing, [], []}) do
    case conflict?(params, context) do
      nil ->
        do_insert(params, context)

      _conflict ->
        [Record.to_record(params, context)]
    end
  end

  defp upsert(context, params, {fields, [], []}) when is_list(fields) do
    all_fields = context.schema_meta.schema.__schema__(:fields)

    case all_fields -- fields do
      [] ->
        # ie replace_all
        do_insert(params, context)

      _ ->
        case conflict?(params, context) do
          nil ->
            do_insert(params, context)

          conflict ->
            orig = Record.to_keyword(conflict, context)
            new = Record.gen_id(params, context)

            record =
              orig
              |> Record.update(new, fields, context)
              |> Record.to_record(context)

            with :ok <- :mnesia.write(context.table_name, record, :write), do: [record]
        end
    end
  end

  defp do_insert(params, context) do
    record =
      params
      |> Record.gen_id(context)
      |> Record.to_record(context)

    with :ok <- :mnesia.write(context.table_name, record, :write), do: [record]
  end

  defp conflict?(params, context) do
    params
    |> Record.key(context)
    |> case do
      nil ->
        nil

      id ->
        case :mnesia.read(context.table_name, id, :read) do
          [] -> nil
          [rec] -> rec
        end
    end
  end
end
