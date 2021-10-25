defmodule Ecto.Adapters.Mnesia.Migrator do
  @moduledoc """
  Lower level API for managing migrations
  """
  alias Ecto.Adapters.Mnesia.Migration

  @doc false
  @spec run(module(), [module()]) :: [module()]
  def run(repo, migrations) do
    Enum.reduce(migrations, [], fn {schema, opts}, acc ->
      case create_table(repo, schema, opts) do
        {:ok, table} ->
          Mix.shell().info("Creates DB table #{table}")
          [schema | acc]

        {:ignore, table} ->
          Mix.shell().info("DB table already exists #{table}")

        {:error, error} ->
          Mix.raise("Coud not create DB table for #{schema}, error: #{inspect(error)}")
      end
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
