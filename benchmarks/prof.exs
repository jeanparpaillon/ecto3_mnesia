
defmodule ProfRepo do
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

defmodule ProfUtils do
  def setup do
    Mnesia.ensure_all_started([], :permanent)
    Ecto.Adapters.Mnesia.storage_up([])
    {:ok, _repo} = ProfRepo.start_link()
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

  def provision(n) do
    1..n
    |> Enum.each(fn x ->
      {:ok, _} = ProfRepo.insert(
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

defmodule ProfRunner do
  def run(name, args) do
    :fprof.apply(__MODULE__, name, args)
    :fprof.profile()
    :fprof.analyse([
      callers: true,
      sort: :own,
      totals: true,
      details: true
    ])
  end

  def all_get_idx(indexes) do
    Enum.each(indexes, &get_int_idx/1)
  end

  def get_id(x) do
    item = ProfRepo.get(TestSchema, x)
    if item.indexed_field != "field-#{x}" do
      IO.puts("ERROR, got wrong value")
      IO.inspect(item)
      exit(1)
    end
  end

  def all_int_idx(indexes) do
    Enum.each(indexes, &get_int_idx/1)
  end

  def get_int_idx(x) do
    item = ProfRepo.get_by(TestSchema, indexed_int_field: x)
    if item.indexed_field != "field-#{x}" do
      IO.puts("ERROR, got wrong value")
      IO.inspect(item)
      exit(1)
    end
  end
end

n = 10

Logger.configure(level: :info)

ProfUtils.setup()
ProfUtils.provision(n)

ProfRunner.run(:get_int_idx, [5])

:mnesia.clear_table(:test_table)
