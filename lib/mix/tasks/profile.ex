# credo:disable-for-this-file
defmodule Mix.Tasks.Profile do
  @moduledoc """
  Run profiling
  """
  @shortdoc "Run profiling"

  use Mix.Task

  require Logger

  alias Ecto.Adapters.Mnesia.Benchmark.Queries
  alias Ecto.Adapters.Mnesia.Benchmark.Repo
  alias Ecto.Adapters.Mnesia.Benchmark.Schema

  @default_n 1000

  @base_dir Path.join(__DIR__, "../../../profile") |> Path.expand()
  @mnesia_dir Path.join(@base_dir, "mnesia") |> to_charlist()

  @impl Mix.Task
  def run(args) do
    n =
      case args do
        [n | _] -> String.to_integer(n)
        _ -> @default_n
      end

    Mix.shell().info("Setting up database")
    setup()

    Mix.shell().info("Provisioning database")
    provision(n)
    # Just for debugging
    # traverse_table_and_show(:test_table)

    try do
      :fprof.apply(Queries, :get_int_idx, [5])
      :fprof.profile()

      :fprof.analyse(
        callers: true,
        sort: :own,
        totals: true,
        details: true
      )
    after
      cleanup()
    end
  end

  defp setup do
    File.mkdir_p!(@base_dir)

    Application.put_env(:ecto3_mnesia, :ecto_repos, [Repo], persistent: true)
    Application.put_env(:mnesia, :dir, @mnesia_dir, persistent: true)

    Mix.Task.run("ecto.create", [])

    Application.ensure_all_started(:ecto3_mnesia)

    Logger.configure(level: :info)

    {:ok, _repo} = Repo.start_link()

    :mnesia.create_table(:test_table,
      disc_copies: [node()],
      record_name: Schema,
      attributes: [
        :id,
        :indexed_int_field,
        :non_indexed_int_field,
        :indexed_field,
        :non_indexed_field,
        :inserted_at,
        :updated_at
      ],
      # storage_properties: [ets: [:compressed]],
      type: :ordered_set,
      index: [:indexed_int_field, :indexed_field]
    )

    :mnesia.wait_for_tables([:test_table], 1000)
    :mnesia.clear_table(:test_table)
  end

  defp provision(n) do
    1..n
    |> Enum.each(fn x ->
      {:ok, _} =
        Repo.insert(%Schema{
          indexed_int_field: x,
          non_indexed_int_field: x,
          indexed_field: "field-#{x}",
          non_indexed_field: "field-#{x}"
        })
    end)
  end

  defp cleanup do
    Mix.Task.run("ecto.drop", [])
    File.rm_rf!(@base_dir)
  end
end
