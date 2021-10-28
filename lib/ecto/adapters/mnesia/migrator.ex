defmodule Ecto.Adapters.Mnesia.Migrator do
  @moduledoc """
  Lower level API for managing migrations
  """
  require Logger

  alias Ecto.Adapters.Mnesia.Connection
  alias Ecto.Adapters.Mnesia.Migration

  @type table_copy :: :ram | :disc
  @type default_copy_opt :: {:default_copy, table_copy()}
  @type schemas_opt :: [module() | {module(), table_copy()} | {module, Keyword.t()}]
  @type migrations_opts :: [default_copy_opt() | [schemas_opt()]]
  @type options :: [{:sync, boolean()}]

  @doc false
  @spec run(module(), [Migration.t()], options()) :: [module()]
  def run(repo, migrations, options \\ []) do
    repo.checkout(fn ->
      tables = do_run_migrations(repo, migrations)

      if Keyword.get(options, :sync, false) do
        Connection.add_waited_schemas(tables)
      end

      tables
    end)
  end

  @doc false
  def with_repo(repo, fun, opts \\ []) do
    config = repo.config()
    mode = Keyword.get(opts, :mode, :permanent)
    apps = [:ecto3_mnesia | config[:start_apps_before_migration] || []]

    extra_started =
      Enum.flat_map(apps, fn app ->
        {:ok, started} = Application.ensure_all_started(app, mode)
        started
      end)

    {:ok, repo_started} = repo.__adapter__().ensure_all_started(config, mode)
    started = extra_started ++ repo_started
    migration_repo = config[:migration_repo] || repo

    case ensure_repo_started(repo, config) do
      {:ok, repo_after} ->
        case ensure_migration_repo_started(migration_repo, repo) do
          {:ok, migration_repo_after} ->
            try do
              {:ok, fun.(repo), started}
            after
              after_action(repo, repo_after)
              after_action(migration_repo, migration_repo_after)
            end

          {:error, _} = error ->
            after_action(repo, repo_after)
            error
        end

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Compile migrations configuration into migrations usable by `run/2`
  """
  @spec compile(migrations_opts()) :: [Migration.t()]
  def compile(opts) do
    default_opts =
      opts
      |> Keyword.get(:default_copy, :disc)
      |> case do
        :disc -> [disc_copies: [node()], ram_copies: []]
        :ram -> [disc_copies: [], ram_copies: [node()]]
      end

    opts
    |> Keyword.get(:schemas, [])
    |> Enum.map(fn
      {schema, storage} when storage in [:ram] ->
        opts =
          default_opts
          |> Keyword.drop([:ram_copies, :disc_copies])
          |> Keyword.merge(ram_copies: [node()], disc_copies: [])

        {schema, opts}

      {schema, storage} when storage in [:disc] ->
        opts =
          default_opts
          |> Keyword.drop([:ram_copies, :disc_copies])
          |> Keyword.merge(ram_copies: [], disc_copies: [node()])

        {schema, opts}

      {schema, opts} when is_list(opts) ->
        {schema, Keyword.merge(default_opts, opts)}

      schema ->
        {schema, default_opts}
    end)
    |> Enum.map(fn {schema, opts} ->
      _ =
        schema
        |> ensure_schema!()
        |> ensure_source!()

      {schema, opts}
    end)
  end

  defp do_run_migrations(repo, migrations) do
    Enum.reduce(migrations, [], fn {schema, opts}, acc ->
      case create_table(repo, schema, opts) do
        {:ok, table} ->
          Logger.info("Creates DB table #{table}")
          [schema | acc]

        {:ignore, table} ->
          Logger.info("DB table already exists #{table}")
          [schema | acc]

        {:error, error} ->
          Logger.error("Coud not create DB table for #{schema}, error: #{inspect(error)}")
          raise "Error running migrations"
      end
    end)
  end

  defp ensure_schema!(schema) do
    case Code.ensure_compiled(schema) do
      {:module, _} ->
        if function_exported?(schema, :__schema__, 2) do
          schema
        else
          Mix.raise("Module #{inspect(schema)} is not an Ecto.Schema.")
        end

      {:error, error} ->
        Mix.raise("Could not load #{inspect(schema)}, error: #{inspect(error)}.")
    end
  end

  defp ensure_source!(schema) do
    case schema.__schema__(:source) do
      nil ->
        Mix.raise(
          "Module #{inspect(schema)} do not define a `:source`, probably an embedded schema."
        )

      _ ->
        schema
    end
  end

  defp ensure_repo_started(repo, config) do
    case repo.start_link(config) do
      {:ok, _} ->
        {:ok, :stop}

      {:error, {:already_started, _pid}} ->
        {:ok, :restart}

      {:error, _} = error ->
        error
    end
  end

  defp ensure_migration_repo_started(repo, repo) do
    {:ok, :noop}
  end

  defp ensure_migration_repo_started(migration_repo, _repo) do
    case migration_repo.start_link(migration_repo.config()) do
      {:ok, _} ->
        {:ok, :stop}

      {:error, {:already_started, _pid}} ->
        {:ok, :noop}

      {:error, _} = error ->
        error
    end
  end

  defp after_action(repo, :restart) do
    if Process.whereis(repo) do
      %{pid: pid} = Ecto.Adapter.lookup_meta(repo)
      Supervisor.restart_child(repo, pid)
    end
  end

  defp after_action(repo, :stop) do
    repo.stop()
  end

  defp after_action(_repo, :noop) do
    :noop
  end

  defp create_table(repo, model, opts) do
    mnesia_opts = Keyword.merge(opts, index: indices(model))

    table = model.__schema__(:source)

    model
    |> constraints()
    |> Enum.each(fn {:foreign_key, from, assoc, opts} ->
      :ok = Migration.references(from, assoc, opts)
    end)

    case Migration.create_table(repo, model, mnesia_opts) do
      {:ok, table} -> {:ok, table}
      :ignore -> {:ignore, table}
      {:error, reason} -> {:error, reason}
    end
  end

  defp indices(model) do
    if function_exported?(model, :__mnesia__, 1) do
      model.__mnesia__(:indices)
    else
      []
    end
  end

  defp constraints(model) do
    if function_exported?(model, :__mnesia__, 1) do
      model.__mnesia__(:constraints)
    else
      []
    end
  end
end
