defmodule Mix.Tasks.Mnesia.Migrate do
  @moduledoc """
  Runs the pending migrations for the given repository.

  The repositories to migrate are the ones specified under the
  `:ecto_repos` option in the current app configuration. However,
  if the `-r` option is given, it replaces the `:ecto_repos` config.

  Since Ecto tasks can only be executed once, if you need to migrate
  multiple repositories, set `:ecto_repos` accordingly or pass the `-r`
  flag multiple times.

  If a repository has not yet been started, one will be started outside
  your application supervision tree and shutdown afterwards.

  ## Command line options

  * `-r`, `--repo` - the repo to migrate
  """
  @shortdoc "Creates Mnesia tables"

  use Mix.Task

  import Mix.Mnesia

  alias Ecto.Adapters.Mnesia.Migrator

  @aliases [
    r: :repo
  ]

  @switches [
    repo: [:keep, :string]
  ]

  @impl Mix.Task
  def run(args) do
    repos = parse_repo(args)
    {opts, _} = OptionParser.parse! args, strict: @switches, aliases: @aliases

    # Start ecto_sql explicitly before as we don't need
    # to restart those apps if migrated.
    {:ok, _} = Application.ensure_all_started(:ecto3_mnesia)

    migrations =
      args
      |> get_migrations()
      |> Enum.filter(fn {_schema, opts} ->
        case Keyword.get(opts, :disc_copies, []) do
          [] -> false
          _ -> true
        end
      end)

    for repo <- repos do
      ensure_repo(repo, args)

      fun = &Migrator.run(&1, migrations)

      case Migrator.with_repo(repo, fun, [mode: :temporary] ++ opts) do
        {:ok, _migrated, _apps} -> :ok
        {:error, error} -> Mix.raise "Could not start repo #{inspect repo}, error: #{inspect error}"
      end
    end
  end
end
