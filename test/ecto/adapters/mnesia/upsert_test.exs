defmodule Ecto.Adapters.Mnesia.UpsertTest do
  use ExUnit.Case, async: false

  require Record

  Record.defrecord(:rec, [:id, :field1, :field2, :field3, :inserted_at, :updated_at])

  alias EctoMnesia.TestRepo
  alias Ecto.Adapters.Mnesia

  @table_name __MODULE__.Table

  defmodule TestSchema do
    use Ecto.Schema

    schema "#{Ecto.Adapters.Mnesia.UpsertTest.Table}" do
      timestamps()

      field(:field1, :string)
      field(:field2, :string)
      field(:field3, :string)
    end

    def changeset(%TestSchema{} = struct, params) do
      struct
      |> Ecto.Changeset.cast(params, [:field1, :field2, :field3])
    end

    defimpl Ecto.Adapters.Mnesia.Recordable do
      def record_name(_), do: :rec

      def load(struct, record, context),
        do: Ecto.Adapters.Mnesia.Recordable.impl_for(nil).load(struct, record, context)

      def dump(struct, params, context),
        do: Ecto.Adapters.Mnesia.Recordable.impl_for(nil).dump(struct, params, context)

      def key(struct, params, context),
        do: Ecto.Adapters.Mnesia.Recordable.impl_for(nil).key(struct, params, context)
    end
  end

  setup_all do
    ExUnit.CaptureLog.capture_log(fn -> Mnesia.storage_up(nodes: [node()]) end)
    Mnesia.ensure_all_started([], :permanent)
    {:ok, _repo} = TestRepo.start_link()

    :mnesia.create_table(@table_name,
      ram_copies: [node()],
      record_name: :rec,
      attributes: [:id, :field1, :field2, :field3, :inserted_at, :updated_at],
      storage_properties: [ets: [:compressed]],
      type: :ordered_set
    )

    :mnesia.wait_for_tables([@table_name], 1000)

    on_exit(fn ->
      :mnesia.clear_table(@table_name)
    end)

    []
  end

  test "on_conflict: :raise" do
    {:ok, %{id: id, updated_at: updated_at} = model} = insert()

    assert_raise Ecto.ConstraintError, fn ->
      TestRepo.insert(%{model | field1: "newfield1"}, on_conflict: :raise)
    end

    assert [rec(id: ^id, field1: "field1", updated_at: ^updated_at)] =
             :mnesia.dirty_read(@table_name, id)
  end

  test "on_conflict: :nothing" do
    {:ok, %{id: id, updated_at: updated_at} = model} = insert()

    assert {:ok, %TestSchema{field1: "newfield1"}} =
             TestRepo.insert(%{model | field1: "newfield1"}, on_conflict: :nothing)

    assert [rec(id: ^id, field1: "field1", updated_at: ^updated_at)] =
             :mnesia.dirty_read(@table_name, id)
  end

  test "on_conflict: :replace_all" do
    {:ok, %{id: id, updated_at: updated_at} = model} = insert()

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
               updated_at: new_updated_at
             )
           ] = :mnesia.dirty_read(@table_name, id)

    refute updated_at == new_updated_at
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
               field3: "newfield3",
               updated_at: %NaiveDateTime{}
             )
           ] = :mnesia.dirty_read(@table_name, id)
  end

  test "on_conflict: {:replace, ...}" do
    {:ok, %{id: id, updated_at: updated_at} = model} = insert()

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
               field3: "field3",
               updated_at: ^updated_at
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
