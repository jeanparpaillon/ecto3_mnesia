{:ok, _} = :compile.file(~c'#{Path.join(__DIR__, "qlc_queries.erl")}', [])

require Logger

alias Ecto.Adapters.Mnesia
alias :qlc_queries, as: Qlc

Logger.configure(level: :info)

n = String.to_integer(System.get_env("N", "1000"))
indices = 1..n |> Enum.shuffle()
Logger.info("N=#{n}")

###########################################################################################
#
# Modules
#
###########################################################################################
defmodule BenchRepo do
  use Ecto.Repo,
    otp_app: :ecto3_mnesia,
    adapter: Ecto.Adapters.Mnesia
end

defmodule TestSchema do
  use Ecto.Schema

  schema "test_table" do
    field(:indexed_int_field, :integer)
    field(:non_indexed_int_field, :integer)
    field(:indexed_field, :string)
    field(:non_indexed_field, :string)

    timestamps()
  end

  def changeset(%TestSchema{} = struct, params) do
    struct
    |> Ecto.Changeset.cast(params, [:field])
  end
end

defmodule BenchUtils do
  def setup do
    Mnesia.ensure_all_started([], :permanent)
    Ecto.Adapters.Mnesia.storage_up([])
    {:ok, _repo} = BenchRepo.start_link()

    :mnesia.create_table(:test_table,
      disc_copies: [node()],
      record_name: TestSchema,
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

  def provision(n) do
    1..n
    |> Enum.each(fn x ->
      {:ok, _} =
        BenchRepo.insert(%TestSchema{
          indexed_int_field: x,
          non_indexed_int_field: x,
          indexed_field: "field-#{x}",
          non_indexed_field: "field-#{x}"
        })
    end)
  end

  def cleanup do
    File.rm_rf("qlc_queries.beam")
    Mnesia.storage_down([])
  end

  def traverse_table_and_show(table_name) do
    iterator = fn rec, _ ->
      :io.format("~p~n", [rec])
      []
    end

    case :mnesia.is_transaction() do
      true ->
        :mnesia.foldl(iterator, [], table_name)

      false ->
        exec = fn {fun, tab} -> :mnesia.foldl(fun, [], tab) end
        :mnesia.activity(:transaction, exec, [{iterator, table_name}], :mnesia_frag)
    end
  end

  def do_benchmark(benchmarks, indices) do
    Enum.reduce(benchmarks, %{}, fn {name, fun}, acc ->
      Map.put(acc, name, do_fun(fun, indices))
    end)
  end

  def do_fun(fun, indices) do
    {
      fn -> Enum.map(indices, fn i -> fun.(i) end) end,
      before_each: & &1
    }
  end
end

###########################################################################################
#
# Benchmarks
#
###########################################################################################
source =
  Ecto.Adapters.Mnesia.Source.new(%{
    autogenerate_id: {:id, :id, :id},
    context: nil,
    prefix: nil,
    schema: TestSchema,
    source: "test_table"
  })

benchmarks = %{
  "ecto.get.id" => fn x ->
    item = BenchRepo.get(TestSchema, x)

    if item.indexed_field != "field-#{x}" do
      IO.puts("ERROR, got wrong value")
      IO.inspect(item)
      exit(1)
    end
  end,
  "mnesia.get.id" => fn x ->
    {:ok, item} =
      BenchRepo.transaction(fn ->
        case :mnesia.read(:test_table, x) do
          [] ->
            nil

          [item] ->
            Ecto.Adapters.Mnesia.Record.to_schema(
              item,
              source
            )
        end
      end)

    if item.indexed_field != "field-#{x}" do
      IO.puts("ERROR, got wrong value")
      IO.inspect(item)
      exit(1)
    end
  end,
  "qlc.get.id" => fn x ->
    {:ok, item} =
      BenchRepo.transaction(fn ->
        case Qlc.get(:test_table, x) do
          [] ->
            nil

          [item] ->
            Ecto.Adapters.Mnesia.Record.to_schema(
              item,
              source
            )
        end
      end)

    if item.indexed_field != "field-#{x}" do
      IO.puts("ERROR, got wrong value")
      IO.inspect(item)
      exit(1)
    end
  end,
  "ecto.get.int.idx" => fn x ->
    item = BenchRepo.get_by(TestSchema, indexed_int_field: x)

    if item.indexed_field != "field-#{x}" do
      IO.puts("ERROR, got wrong value")
      IO.inspect(item)
      exit(1)
    end
  end,
  "mnesia.get.int.idx" => fn x ->
    {:ok, item} =
      BenchRepo.transaction(fn ->
        case :mnesia.index_read(:test_table, x, :indexed_int_field) do
          [] ->
            nil

          [item] ->
            Ecto.Adapters.Mnesia.Record.to_schema(
              item,
              source
            )
        end
      end)

    if item.indexed_field != "field-#{x}" do
      IO.puts("ERROR, got wrong value")
      IO.inspect(item)
      exit(1)
    end
  end,
  "ecto.get.string.idx" => fn x ->
    item = BenchRepo.get_by(TestSchema, indexed_field: "field-#{x}")

    if item.indexed_field != "field-#{x}" do
      IO.puts("ERROR, got wrong value")
      IO.inspect(item)
      exit(1)
    end
  end,
  "mnesia.get.string.idx" => fn x ->
    {:ok, item} =
      BenchRepo.transaction(fn ->
        case :mnesia.index_read(:test_table, "field-#{x}", :indexed_field) do
          [] ->
            nil

          [item] ->
            Ecto.Adapters.Mnesia.Record.to_schema(
              item,
              source
            )
        end
      end)

    if item.indexed_field != "field-#{x}" do
      IO.puts("ERROR, got wrong value")
      IO.inspect(item)
      exit(1)
    end
  end,
  "ecto.get.int.non.idx" => fn x ->
    item = BenchRepo.get_by(TestSchema, non_indexed_int_field: x)

    if item.indexed_field != "field-#{x}" do
      IO.puts("ERROR, got wrong value")
      IO.inspect(item)
      exit(1)
    end
  end,
  "mnesia.get.int.non.idx" => fn x ->
    {:ok, item} =
      BenchRepo.transaction(fn ->
        case :mnesia.match_object(:test_table, {:_, :_, :_, x, :_, :_, :_, :_}, :read) do
          [] ->
            nil

          [item] ->
            Ecto.Adapters.Mnesia.Record.to_schema(
              item,
              source
            )
        end
      end)

    if item.indexed_field != "field-#{x}" do
      IO.puts("ERROR, got wrong value")
      IO.inspect(item)
      exit(1)
    end
  end,
  "ecto.get.string.non.idx" => fn x ->
    item = BenchRepo.get_by(TestSchema, non_indexed_field: "field-#{x}")

    if item.indexed_field != "field-#{x}" do
      IO.puts("ERROR, got wrong value")
      IO.inspect(item)
      exit(1)
    end
  end,
  "mnesia.get.string.non.idx" => fn x ->
    {:ok, item} =
      BenchRepo.transaction(fn ->
        case :mnesia.match_object(
               :test_table,
               {:_, :_, :_, :_, :_, "field-#{x}", :_, :_},
               :read
             ) do
          [] ->
            nil

          [item] ->
            Ecto.Adapters.Mnesia.Record.to_schema(
              item,
              source
            )
        end
      end)

    if item.indexed_field != "field-#{x}" do
      IO.puts("ERROR, got wrong value")
      IO.inspect(item)
      exit(1)
    end
  end
}

###########################################################################################
#
# Execution
#
###########################################################################################
BenchUtils.setup()
BenchUtils.provision(n)
# Just for debugging
# BenchUtils.traverse_table_and_show(:test_table)

Benchee.run(
  BenchUtils.do_benchmark(
    benchmarks |> Map.take(["ecto.get.id", "mnesia.get.id", "qlc.get.id"]),
    indices),
  time: 10,
  memory_time: 2,
  formatters: [
    Benchee.Formatters.HTML,
    # {Benchee.Formatters.JSON, file: "output/json/provision.json"},
    Benchee.Formatters.Console
  ],
  before_each: & &1
)

BenchUtils.cleanup()
