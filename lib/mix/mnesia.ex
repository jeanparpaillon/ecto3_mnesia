defmodule Mix.Mnesia do
  @moduledoc """
  Helpers functions for Mnesia tasks
  """

  @doc """
  Ensures the given module is an Ecto.Repo.
  """
  @spec ensure_repo(module, list) :: Ecto.Repo.t()
  def ensure_repo(repo, args) do
    # Do not pass the --force switch used by some tasks downstream
    args = List.delete(args, "--force")

    # TODO: Use only app.config when we depend on Elixir v1.11+.
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
        # TODO: Use the proper ordering from Mix.Project.deps_apps
        # when we depend on Elixir v1.11+.
        apps_paths |> Map.keys() |> Enum.sort()
      else
        [Mix.Project.config()[:app]]
      end

    apps
    |> Enum.flat_map(fn app ->
      Application.load(app)

      app
      |> Application.get_env(:ecto_migrations, [])
      |> normalize_migration()
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
        # TODO: Use the proper ordering from Mix.Project.deps_apps
        # when we depend on Elixir v1.11+.
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

  defp normalize_migration(kw) do
    default_opts =
      kw
      |> Keyword.get(:default_copy, :disc)
      |> case do
        :disc -> [disc_copies: [node()], ram_copies: []]
        :ram -> [disc_copies: [], ram_copies: [node()]]
      end

    kw
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
      _ = ensure_schema!(schema)
      {schema, opts}
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
end
