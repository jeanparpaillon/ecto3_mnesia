
defmodule BenchRepo do
  use Ecto.Repo,
  otp_app: :ecto3_mnesia,
  adapter: Ecto.Adapters.Mnesia
end

alias Ecto.Adapters.Mnesia

defmodule TestSchema do
  use Ecto.Schema

  schema "test_table" do
    field(:field, :string)

    timestamps()
  end

  def changeset(%TestSchema{} = struct, params) do
    struct
    |> Ecto.Changeset.cast(params, [:field])
  end
end

defmodule Utils do
  def setup do
    Mnesia.ensure_all_started([], :permanent)
    {:ok, _repo} = BenchRepo.start_link()
    :mnesia.create_table(:test_table,
      disc_copies: [node()],
      record_name: TestSchema,
      attributes: [:id, :field, :inserted_at, :updated_at],
      # storage_properties: [ets: [:compressed]],
      type: :ordered_set
      )
      :mnesia.wait_for_tables([:test_table], 1000)
  end

  def provision do
    1..1000
    |> Enum.each(fn x ->
      {:ok, _} = BenchRepo.insert(%TestSchema{field: "field-#{x}"})
    end)
  end
end

Utils.setup()
Utils.provision()

indexes = 1..1000 |> Enum.map(fn _ -> Enum.random(1..1000) end)
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
    "ecto.get" => {
      fn ->
        Enum.map(
          indexes,
          fn x ->
            item = BenchRepo.get(TestSchema, x)
            if item.field != "field-#{x}" do
              IO.puts("ERROR, got wrong value")
              IO.inspect(item)
              exit(1)
            end
          end)
      end,
      before_each: fn input ->
        # Udm.SupiKeys.delete_all()
        input
      end
    },
    "mnesia.get" => {
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
              if item.field != "field-#{x}" do
                IO.puts("ERROR, got wrong value")
                IO.inspect(item)
                exit(1)
              end
          end)
      end,
      before_each: fn input ->
        input
      end
    }
  },
  time: 1,
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
  #   Udm.SupiKeys.delete_all()
  #   Udm.Provision.Supi.delete_all()
  #   input
  # end
)

:mnesia.clear_table(:test_table)
