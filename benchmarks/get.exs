
defmodule BenchRepo do
  use Ecto.Repo,
  otp_app: :ecto3_mnesia,
  adapter: Ecto.Adapters.Mnesia
end

alias Ecto.Adapters.Mnesia

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
        :updated_at],
      # storage_properties: [ets: [:compressed]],
      type: :ordered_set,
      index: [:indexed_int_field, :indexed_field]
      )
      :mnesia.wait_for_tables([:test_table], 1000)
      :mnesia.clear_table(:test_table)
  end

  def provision do
    1..1000
    |> Enum.each(fn x ->
      {:ok, _} = BenchRepo.insert(
        %TestSchema{
          indexed_int_field: x,
          non_indexed_int_field: x,
          indexed_field: "field-#{x}",
          non_indexed_field: "field-#{x}"
        }
      )
    end)
  end

  def traverse_table_and_show(table_name) do
    iterator =  fn rec, _ ->
                    :io.format("~p~n",[rec])
                    []
                end
    case :mnesia.is_transaction() do
        true -> :mnesia.foldl(iterator, [], table_name)
        false ->
            exec = fn {fun, tab} -> :mnesia.foldl(fun, [], tab) end
            :mnesia.activity(:transaction, exec, [{iterator, table_name}], :mnesia_frag)
    end
  end
end

BenchUtils.setup()
BenchUtils.provision()
# Just for debugging
# BenchUtils.traverse_table_and_show(:test_table)

range = 1..1000
indexes = range |> Enum.map(fn _ -> Enum.random(range) end)

# Hack to get record translation added to bench
source = Ecto.Adapters.Mnesia.Source.new(
  %{
    autogenerate_id: {:id, :id, :id},
    context: nil,
    prefix: nil,
    schema: TestSchema,
    source: "test_table"
  }
)

Benchee.run(
  %{
    "ecto.get.id" => {
      fn ->
        Enum.map(
          indexes,
          fn x ->
            item = BenchRepo.get(TestSchema, x)
            if item.indexed_field != "field-#{x}" do
              IO.puts("ERROR, got wrong value")
              IO.inspect(item)
              exit(1)
            end
          end)
      end,
      before_each: fn input ->
        input
      end
    },
    "mnesia.get.id" => {
      fn ->
        Enum.map(
          indexes,
          fn x ->
            {:ok, item} =
              BenchRepo.transaction(fn ->
                case :mnesia.read(:test_table, x) do
                  [] ->
                    nil

                  [item] ->
                    Ecto.Adapters.Mnesia.Record.to_schema(
                      item,
                      source)
                end
              end)
              if item.indexed_field != "field-#{x}" do
                IO.puts("ERROR, got wrong value")
                IO.inspect(item)
                exit(1)
              end
          end)
      end,
      before_each: fn input ->
        input
      end
    },
    "ecto.get.int.idx" => {
      fn ->
        Enum.map(
          indexes,
          fn x ->
            item = BenchRepo.get_by(TestSchema, indexed_int_field: x)
            if item.indexed_field != "field-#{x}" do
              IO.puts("ERROR, got wrong value")
              IO.inspect(item)
              exit(1)
            end
          end)
      end,
      before_each: fn input ->
        input
      end
    },
    "mnesia.get.int.idx" => {
      fn ->
        Enum.map(
          indexes,
          fn x ->
            {:ok, item} =
              BenchRepo.transaction(fn ->
                case :mnesia.index_read(:test_table, x, :indexed_int_field) do
                  [] ->
                    nil

                  [item] ->
                    Ecto.Adapters.Mnesia.Record.to_schema(
                      item,
                      source)
                end
              end)
              if item.indexed_field != "field-#{x}" do
                IO.puts("ERROR, got wrong value")
                IO.inspect(item)
                exit(1)
              end
          end)
      end,
      before_each: fn input ->
        input
      end
    },
    "ecto.get.string.idx" => {
      fn ->
        Enum.map(
          indexes,
          fn x ->
            item = BenchRepo.get_by(TestSchema, indexed_field: "field-#{x}")
            if item.indexed_field != "field-#{x}" do
              IO.puts("ERROR, got wrong value")
              IO.inspect(item)
              exit(1)
            end
          end)
      end,
      before_each: fn input ->
        input
      end
    },
    "mnesia.get.string.idx" => {
      fn ->
        Enum.map(
          indexes,
          fn x ->
            {:ok, item} =
              BenchRepo.transaction(fn ->
                case :mnesia.index_read(:test_table, "field-#{x}", :indexed_field) do
                  [] ->
                    nil

                  [item] ->
                    Ecto.Adapters.Mnesia.Record.to_schema(
                      item,
                      source)
                end
              end)
              if item.indexed_field != "field-#{x}" do
                IO.puts("ERROR, got wrong value")
                IO.inspect(item)
                exit(1)
              end
          end)
      end,
      before_each: fn input ->
        input
      end
    },
    "ecto.get.int.non.idx" => {
      fn ->
        Enum.map(
          indexes,
          fn x ->
            item = BenchRepo.get_by(TestSchema, non_indexed_int_field: x)
            if item.indexed_field != "field-#{x}" do
              IO.puts("ERROR, got wrong value")
              IO.inspect(item)
              exit(1)
            end
          end)
      end,
      before_each: fn input ->
        input
      end
    },
    "mnesia.get.int.non.idx" => {
      fn ->
        Enum.map(
          indexes,
          fn x ->
            {:ok, item} =
              BenchRepo.transaction(fn ->
                case :mnesia.match_object(:test_table, {:_, :_, :_, x, :_, :_, :_, :_}, :read) do
                  [] ->
                    nil

                  [item] ->
                    Ecto.Adapters.Mnesia.Record.to_schema(
                      item,
                      source)
                end
              end)
              if item.indexed_field != "field-#{x}" do
                IO.puts("ERROR, got wrong value")
                IO.inspect(item)
                exit(1)
              end
          end)
      end,
      before_each: fn input ->
        input
      end
    },
    "ecto.get.string.non.idx" => {
      fn ->
        Enum.map(
          indexes,
          fn x ->
            item = BenchRepo.get_by(TestSchema, non_indexed_field: "field-#{x}")
            if item.indexed_field != "field-#{x}" do
              IO.puts("ERROR, got wrong value")
              IO.inspect(item)
              exit(1)
            end
          end)
      end,
      before_each: fn input ->
        input
      end
    },
    "mnesia.get.string.non.idx" => {
      fn ->
        Enum.map(
          indexes,
          fn x ->
            {:ok, item} =
              BenchRepo.transaction(fn ->
                case :mnesia.match_object(:test_table, {:_, :_, :_, :_, :_, "field-#{x}", :_, :_}, :read) do
                  [] ->
                    nil

                  [item] ->
                    Ecto.Adapters.Mnesia.Record.to_schema(
                      item,
                      source)
                end
              end)
              if item.indexed_field != "field-#{x}" do
                IO.puts("ERROR, got wrong value")
                IO.inspect(item)
                exit(1)
              end
          end)
      end,
      before_each: fn input ->
        input
      end,
      before_each: fn input ->
        input
      end
    }
  },
  time: 10,
  memory_time: 2,
  formatters: [
    Benchee.Formatters.HTML,
    # {Benchee.Formatters.JSON, file: "output/json/provision.json"},
    Benchee.Formatters.Console
  ],
  before_each: fn input ->
    input
  end
  # before_scenario: fn input ->
  #   input
  # end
)

:mnesia.clear_table(:test_table)
