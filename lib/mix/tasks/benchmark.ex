defmodule Mix.Tasks.Benchmark do
  @moduledoc """
  Run benchmark
  """
  @shortdoc "Run benchmark"

  use Mix.Task

  require Logger

  alias Ecto.Adapters.Mnesia.Benchmark.Queries
  alias Ecto.Adapters.Mnesia.Benchmark.Repo
  alias Ecto.Adapters.Mnesia.Benchmark.Schema

  @default_n 1000
  @mnesia_dir Path.join(__DIR__, "../../../benchmarks/mnesia") |> Path.expand() |> to_charlist()

  @impl Mix.Task
  def run(args) do
    n =
      case args do
        [n | _] -> String.to_integer(n)
        _ -> @default_n
      end

    indices = 1..n |> Enum.shuffle()

    Mix.shell().info("Setting up database")
    setup()

    Mix.shell().info("Provisioning database")
    provision(n)
    # Just for debugging
    # traverse_table_and_show(:test_table)

    try do
      opts = [
        time: 10,
        memory_time: 2,
        formatters: [
          Benchee.Formatters.HTML,
          # {Benchee.Formatters.JSON, file: "output/json/provision.json"},
          Benchee.Formatters.Console
        ],
        before_each: & &1
      ]

      Benchee.run(benchmarks(indices), opts)
    after
      cleanup()
    end
  end

  defp benchmarks(indices) do
    %{
      "ecto.get.id" => &Queries.ecto_get_id/1,
      "mnesia.get.id" => &Queries.mnesia_get_id/1,
      "qlc.get.id" => &Queries.qlc_get_id/1,
      "ecto.get.int.idx" => &Queries.ecto_get_int_idx/1,
      "mnesia.get.int.idx" => &Queries.mnesia_get_int_idx/1,
      "qlc.get.int.idx" => &Queries.qlc_get_int_idx/1,
      "ecto.get.string.idx" => &Queries.ecto_get_int_idx/1,
      "mnesia.get.string.idx" => &Queries.mnesia_get_string_idx/1,
      "qlc.get.string.idx" => &Queries.qlc_get_string_idx/1,
      "ecto.get.int.non.idx" => &Queries.ecto_get_int_non_idx/1,
      "mnesia.get.int.non.idx" => &Queries.mnesia_get_int_non_idx/1,
      "qlc.get.int.non.idx" => &Queries.qlc_get_int_non_idx/1,
      "ecto.get.string.non.idx" => &Queries.ecto_get_string_non_idx/1,
      "mnesia.get.string.non.idx" => &Queries.mnesia_get_string_non_idx/1,
      "qlc.get.string.non.idx" => &Queries.qlc_get_string_non_idx/1
    }
    |> Enum.reduce(%{}, fn {name, fun}, acc ->
      Map.put(acc, name, do_fun(fun, indices))
    end)
  end

  defp setup do
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
  end

  # @doc false
  # def traverse_table_and_show(table_name) do
  #   iterator = fn rec, _ ->
  #     :io.format("~p~n", [rec])
  #     []
  #   end

  #   case :mnesia.is_transaction() do
  #     true ->
  #       :mnesia.foldl(iterator, [], table_name)

  #     false ->
  #       exec = fn {fun, tab} -> :mnesia.foldl(fun, [], tab) end
  #       :mnesia.activity(:transaction, exec, [{iterator, table_name}], :mnesia_frag)
  #   end
  # end

  defp do_fun(fun, indices) do
    {
      fn -> Enum.map(indices, fn i -> fun.(i) end) end,
      before_each: & &1
    }
  end
end
