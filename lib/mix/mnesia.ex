defmodule Mix.Mnesia do
  @moduledoc """
  Helpers functions for Mnesia tasks
  """
  alias Ecto.Adapters.Mnesia.Migrator

  @doc """
  Ensures the given module is an Ecto.Repo.
  """
  @spec ensure_repo(module, list) :: Ecto.Repo.t()
  def ensure_repo(repo, args) do
    # Do not pass the --force switch used by some tasks downstream
    args = List.delete(args, "--force")

    if Code.ensure_loaded?(Mix.Tasks.App.Config) do
      Mix.Task.run("app.config", args)
    else
      Mix.Task.run("loadpaths", args)
      "--no-compile" not in args && Mix.Task.run("compile", args)
    end

    case Code.ensure_compiled(repo) do
      {:module, _} ->
        if function_exported?(repo, :__adapter__, 0) do
          repo
        else
          Mix.raise(
            "Module #{inspect(repo)} is not an Ecto.Repo. " <>
              "Please configure your app accordingly or pass a repo with the -r option."
          )
        end

      {:error, error} ->
        Mix.raise(
          "Could not load #{inspect(repo)}, error: #{inspect(error)}. " <>
            "Please configure your app accordingly or pass a repo with the -r option."
        )
    end
  end

  @doc """
  Returns migrations from environment
  """
  def get_migrations(args) do
    if Code.ensure_loaded?(Mix.Tasks.App.Config) do
      Mix.Task.run("app.config", args)
    else
      Mix.Task.run("loadpaths", args)
      "--no-compile" not in args && Mix.Task.run("compile", args)
    end

    apps =
      if apps_paths = Mix.Project.apps_paths() do
        apps_paths |> Map.keys() |> Enum.sort()
      else
        [Mix.Project.config()[:app]]
      end

    apps
    |> Enum.flat_map(fn app ->
      Application.load(app)

      app
      |> Application.get_env(:ecto_migrations, [])
      |> Migrator.compile()
    end)
    |> Enum.uniq()
  end

  @doc """
  Parses the repository option from the given command line args list.

  If no repo option is given, it is retrieved from the application environment.
  """
  @spec parse_repo([term]) :: [Ecto.Repo.t()]
  def parse_repo(args) do
    parse_repo(args, [])
  end

  defp parse_repo([key, value | t], acc) when key in ~w(--repo -r) do
    parse_repo(t, [Module.concat([value]) | acc])
  end

  defp parse_repo([_ | t], acc) do
    parse_repo(t, acc)
  end

  defp parse_repo([], []) do
    apps =
      if apps_paths = Mix.Project.apps_paths() do
        apps_paths |> Map.keys() |> Enum.sort()
      else
        [Mix.Project.config()[:app]]
      end

    apps
    |> Enum.flat_map(fn app ->
      Application.load(app)
      Application.get_env(app, :ecto_repos, [])
    end)
    |> Enum.uniq()
    |> case do
      [] ->
        Mix.shell().error("""
        warning: could not find Ecto repos in any of the apps: #{inspect(apps)}.

        You can avoid this warning by passing the -r flag or by setting the
        repositories managed by those applications in your config/config.exs:

            config #{inspect(hd(apps))}, ecto_repos: [...]
        """)

        []

      repos ->
        repos
    end
  end

  defp parse_repo([], acc) do
    Enum.reverse(acc)
  end
end
