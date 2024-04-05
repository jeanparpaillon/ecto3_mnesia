defmodule Ecto.Adapters.Mnesia.AutogenerateTest do
  use Ecto.Adapters.Mnesia.RepoCase, async: false

  alias Ecto.Adapters.Mnesia

  @table_name __MODULE__.Table

  defmodule TestSchema do
    use Ecto.Schema

    @primary_key false
    schema "#{Ecto.Adapters.Mnesia.AutogenerateTest.Table}" do
      field(:id, :id, autogenerate: true, primary_key: true, source: :pkey)
      field(:field, :string)
      timestamps()
    end
  end

  setup_all do
    :ok = Mnesia.Migration.sync_create_table(Repo, TestSchema)

    []
  end

  test "autogenerated id increment" do
    {:ok, %TestSchema{id: id}} = Repo.insert(%TestSchema{field: "value"})

    assert is_integer(id)
    assert id == Mnesia.next_id(@table_name, :pkey) - 1
  end
end
