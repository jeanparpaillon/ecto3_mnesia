defmodule Ecto.Adapters.Mnesia.AutogenerateTest do
  use ExUnit.Case, async: false

  alias EctoMnesia.TestRepo, as: Repo
  alias Ecto.Adapters.Mnesia

  @table_name __MODULE__.Table

  defmodule TestSchema do
    use Ecto.Schema

    @primary_key false
    schema "#{Ecto.Adapters.Mnesia.AutogenerateTest.Table}" do
      field :id, :id, autogenerate: true, primary_key: true, source: :pkey
      field :field, :string
      timestamps()
    end
  end

  setup_all do
    ExUnit.CaptureLog.capture_log(fn -> Mnesia.storage_up(nodes: [node()]) end)

    Mnesia.ensure_all_started([], :permanent)
    {:ok, _repo} = Repo.start_link()

    _ = Mnesia.Migration.create_table(TestSchema)
    :mnesia.wait_for_tables([@table_name], 1000)

    on_exit(fn ->
      :mnesia.clear_table(@table_name)
    end)

    []
  end

  test "autogenerated id increment" do
    {:ok, %TestSchema{id: id}} = Repo.insert(%TestSchema{field: "value"})

    assert is_integer(id)

    assert id == Mnesia.autogenerate({{@table_name, :pkey}, :id}) - 1
  end
end
