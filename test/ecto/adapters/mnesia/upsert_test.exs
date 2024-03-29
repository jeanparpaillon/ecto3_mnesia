defmodule Ecto.Adapters.Mnesia.UpsertTest do
  use Ecto.Adapters.Mnesia.RepoCase, async: false

  require Record

  Record.defrecord(:rec, [:id, :field1, :field2, :field3, :inserted_at, :updated_at])

  alias Ecto.Adapters.Mnesia
  alias Ecto.Adapters.Mnesia.Type
  alias EctoMnesia.TestRepo

  @table_name __MODULE__.Table

  defmodule TestSchema do
    use Ecto.Schema

    schema "#{Ecto.Adapters.Mnesia.UpsertTest.Table}" do
      field(:field1, :string)
      field(:field2, :string)
      field(:field3, :string)

      timestamps()
    end

    def changeset(%TestSchema{} = struct, params) do
      struct
      |> Ecto.Changeset.cast(params, [:field1, :field2, :field3])
    end

    def __record_name__, do: :rec
  end

  setup_all do
    :ok =
      Mnesia.Migration.sync_create_table(TestRepo, TestSchema,
        ram_copies: [node()],
        type: :ordered_set
      )

    []
  end

  test "on_conflict: :raise" do
    {:ok, %{id: id, updated_at: updated_at} = model} = insert()
    {:ok, updated_at_ts} = Type.dump_naive_datetime(updated_at, :second)

    assert_raise Ecto.ConstraintError, fn ->
      TestRepo.insert(%{model | field1: "newfield1"}, on_conflict: :raise)
    end

    assert [rec(id: ^id, field1: "field1", updated_at: ^updated_at_ts)] =
             :mnesia.dirty_read(@table_name, id)
  end

  test "on_conflict: :nothing" do
    {:ok, %{id: id, updated_at: updated_at} = model} = insert()
    {:ok, updated_at_ts} = Type.dump_naive_datetime(updated_at, :second)

    assert {:ok, %TestSchema{field1: "newfield1"}} =
             TestRepo.insert(%{model | field1: "newfield1"}, on_conflict: :nothing)

    assert [rec(id: ^id, field1: "field1", updated_at: ^updated_at_ts)] =
             :mnesia.dirty_read(@table_name, id)
  end

  test "on_conflict: :replace_all" do
    {:ok, %{id: id, updated_at: updated_at} = model} = insert()
    {:ok, updated_at_ts} = Type.dump_naive_datetime(updated_at, :second)

    model = %{
      model
      | field1: "newfield1",
        field2: "newfield2",
        field3: "newfield3",
        inserted_at: nil,
        updated_at: nil
    }

    assert {:ok,
            %TestSchema{id: ^id, field1: "newfield1", field2: "newfield2", field3: "newfield3"}} =
             TestRepo.insert(model, on_conflict: :replace_all)

    assert [
             rec(
               id: ^id,
               field1: "newfield1",
               field2: "newfield2",
               field3: "newfield3",
               updated_at: new_updated_at_ts
             )
           ] = :mnesia.dirty_read(@table_name, id)

    refute updated_at_ts == new_updated_at_ts
  end

  test "on_conflict: {:replace_all_except, ...}" do
    {:ok, %{id: id} = model} = insert()

    model = %{
      model
      | field1: "newfield1",
        field2: "newfield2",
        field3: "newfield3",
        updated_at: nil
    }

    assert {:ok, %TestSchema{id: ^id}} =
             TestRepo.insert(model, on_conflict: {:replace_all_except, [:field2, :inserted_at]})

    assert [
             rec(
               id: ^id,
               field1: "newfield1",
               field2: "field2",
               field3: "newfield3"
             )
           ] = :mnesia.dirty_read(@table_name, id)
  end

  test "on_conflict: {:replace, ...}" do
    {:ok, %{id: id} = model} = insert()

    model = %{
      model
      | field1: "newfield1",
        field2: "newfield2",
        field3: "newfield3",
        updated_at: nil
    }

    assert {:ok, %TestSchema{id: ^id}} =
             TestRepo.insert(model, on_conflict: {:replace, [:field2]})

    assert [
             rec(
               id: ^id,
               field1: "field1",
               field2: "newfield2",
               field3: "field3"
             )
           ] = :mnesia.dirty_read(@table_name, id)
  end

  defp insert do
    timestamp =
      NaiveDateTime.utc_now() |> NaiveDateTime.add(-1000) |> NaiveDateTime.truncate(:second)

    %TestSchema{
      field1: "field1",
      field2: "field2",
      field3: "field3",
      inserted_at: timestamp,
      updated_at: timestamp
    }
    |> TestRepo.insert()
  end
end
