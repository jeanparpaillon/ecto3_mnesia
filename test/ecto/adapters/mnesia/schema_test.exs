defmodule Ecto.Adapters.Mnesia.SchemaIntegrationTest do
  use Ecto.Adapters.Mnesia.RepoCase, async: false

  require Ecto.Query

  alias EctoMnesia.TestRepo
  alias Ecto.Adapters.Mnesia

  @table_name __MODULE__.Table
  @alt_record_table_name __MODULE__.AltRecordTable
  @alt_record_name :alt_record
  @array_table_name __MODULE__.ArrayTable
  @binary_id_table_name __MODULE__.BinaryIdTable
  @without_primary_key_table_name __MODULE__.WithoutPrimaryKeyTable
  @multiple_primary_key_table_name __MODULE__.MultiplePrimaryKeyTable

  defmodule TestSchema do
    use Ecto.Schema

    schema "#{Ecto.Adapters.Mnesia.SchemaIntegrationTest.Table}" do
      field(:field, :string)

      timestamps()
    end

    def changeset(%TestSchema{} = struct, params) do
      struct
      |> Ecto.Changeset.cast(params, [:field])
    end
  end

  defmodule TestSchemaAltRecord do
    use Ecto.Schema

    schema "#{Ecto.Adapters.Mnesia.SchemaIntegrationTest.AltRecordTable}" do
      field(:field, :string)
    end

    def changeset(%__MODULE__{} = struct, params) do
      struct
      |> Ecto.Changeset.cast(params, [:field])
    end

    def __record_name__, do: :alt_record
  end

  defmodule ArrayTestSchema do
    use Ecto.Schema

    schema "#{Ecto.Adapters.Mnesia.SchemaIntegrationTest.ArrayTable}" do
      field(:field, {:array, :string})

      timestamps()
    end

    def changeset(%ArrayTestSchema{} = struct, params) do
      struct
      |> Ecto.Changeset.cast(params, [:field])
    end
  end

  defmodule BinaryIdTestSchema do
    use Ecto.Schema

    @primary_key {:id, :binary_id, autogenerate: true}
    schema "#{Ecto.Adapters.Mnesia.SchemaIntegrationTest.BinaryIdTable}" do
      field(:field, :string)

      timestamps()
    end

    def changeset(%TestSchema{} = struct, params) do
      struct
      |> Ecto.Changeset.cast(params, [:field])
    end
  end

  defmodule WithoutPrimaryKeyTestSchema do
    use Ecto.Schema

    @primary_key false
    schema "#{Ecto.Adapters.Mnesia.SchemaIntegrationTest.WithoutPrimaryKeyTable}" do
      field(:field, :string)

      timestamps()
    end

    def changeset(%TestSchema{} = struct, params) do
      struct
      |> Ecto.Changeset.cast(params, [:field])
    end
  end

  defmodule MultiplePrimaryKeyTestSchema do
    use Ecto.Schema

    @primary_key false
    schema "#{Ecto.Adapters.Mnesia.SchemaIntegrationTest.MultiplePrimaryKeyTable}" do
      field(:key1, :id, primary_key: true)
      field(:key2, :id, primary_key: true)
      field(:field, :string)

      timestamps()
    end

    def changeset(%TestSchema{} = struct, params) do
      struct
      |> Ecto.Changeset.cast(params, [:key1, :key2, :field])
    end
  end

  setup_all do
    [
      TestSchema,
      TestSchemaAltRecord,
      ArrayTestSchema,
      BinaryIdTestSchema,
      WithoutPrimaryKeyTestSchema,
      MultiplePrimaryKeyTestSchema
    ]
    |> Enum.each(fn schema ->
      :ok = Mnesia.Migration.sync_create_table(schema, ram_copies: [node()], type: :ordered_set)
    end)
  end

  describe "Ecto.Adapters.Schema#insert" do
    test "Repo#insert valid record" do
      case TestRepo.insert(%TestSchema{field: "field"}) do
        {:ok, %{id: id, field: "field"}} ->
          assert true

          {:atomic, [result]} =
            :mnesia.transaction(fn ->
              :mnesia.read(@table_name, id)
            end)

          {TestSchema, ^id, field, _, _} = result
          assert field == "field"

        _ ->
          assert false
      end

      :mnesia.clear_table(@table_name)
    end

    test "Repo#insert valid record - alt record name" do
      case TestRepo.insert(%TestSchemaAltRecord{field: "field"}) do
        {:ok, %{id: id, field: "field"}} ->
          assert true

          {:atomic, [result]} =
            :mnesia.transaction(fn ->
              :mnesia.read(@alt_record_table_name, id)
            end)

          {@alt_record_name, ^id, field} = result
          assert field == "field"

        _ ->
          assert false
      end

      :mnesia.clear_table(@alt_record_table_name)
    end

    test "Repo#insert valid record with existing record, [on_conflict: :replace_all]" do
      id = 1

      :mnesia.transaction(fn ->
        :mnesia.write(
          @table_name,
          {TestSchema, id, "field", NaiveDateTime.utc_now(), NaiveDateTime.utc_now()},
          :write
        )
      end)

      case TestRepo.insert(%TestSchema{id: id, field: "field"}, on_conflict: :replace_all) do
        {:ok, %{id: id, field: "field"}} ->
          assert true

          {:atomic, [result]} =
            :mnesia.transaction(fn ->
              :mnesia.read(@table_name, id)
            end)

          {TestSchema, ^id, field, _, _} = result
          assert field == "field"

        _ ->
          assert false
      end

      :mnesia.clear_table(@table_name)
    end

    test "Repo#insert valid record with existing record, [on_conflict: :raise]" do
      id = 1

      :mnesia.transaction(fn ->
        :mnesia.write(
          @table_name,
          {TestSchema, id, "field", NaiveDateTime.utc_now(), NaiveDateTime.utc_now()},
          :write
        )
      end)

      assert_raise Ecto.ConstraintError, fn ->
        TestRepo.insert(%TestSchema{id: id, field: "field"}, on_conflict: :raise)
      end

      :mnesia.clear_table(@table_name)
    end

    test "Repo#insert valid record with existing record" do
      id = 1

      :mnesia.transaction(fn ->
        :mnesia.write(
          @table_name,
          {TestSchema, id, "field", NaiveDateTime.utc_now(), NaiveDateTime.utc_now()},
          :write
        )
      end)

      assert_raise Ecto.ConstraintError, fn ->
        TestRepo.insert(%TestSchema{id: id, field: "field"})
      end

      :mnesia.clear_table(@table_name)
    end

    test "Repo#insert valid record with array" do
      array = ["a", "b"]

      case TestRepo.insert(%ArrayTestSchema{field: array}) do
        {:ok, %{id: id}} ->
          assert true

          {:atomic, [{_, _id, field, _, _}]} =
            :mnesia.transaction(fn ->
              :mnesia.read(@array_table_name, id)
            end)

          assert field == array

        _ ->
          assert false
      end

      :mnesia.clear_table(@array_table_name)
    end

    test "Repo#insert valid record with binary id" do
      case TestRepo.insert(%BinaryIdTestSchema{field: "field"}) do
        {:ok, %{id: id, field: "field"}} ->
          assert true

          {:atomic, [{_, id, field, _, _}]} =
            :mnesia.transaction(fn ->
              :mnesia.read(@binary_id_table_name, id)
            end)

          assert id =~
                   ~r([0-9a-fA-F]{8}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{12})

          assert field == "field"

        _ ->
          assert false
      end

      :mnesia.clear_table(@binary_id_table_name)
    end

    test "Repo#insert valid record without primary key" do
      case TestRepo.insert(%WithoutPrimaryKeyTestSchema{field: "field"}) do
        {:ok, %{field: field}} ->
          assert true

          {:atomic, [{_, field, _, _}]} =
            :mnesia.transaction(fn ->
              :mnesia.read(@without_primary_key_table_name, field)
            end)

          assert field == "field"

        _ ->
          assert false
      end

      :mnesia.clear_table(@without_primary_key_table_name)
    end

    test "Repo#insert valid record with returning opt" do
      case TestRepo.insert(%TestSchema{field: "field"}, returning: [:id, :field]) do
        {:ok, %{id: id, field: "field"}} ->
          assert true

          {:atomic, [result]} =
            :mnesia.transaction(fn ->
              :mnesia.read(@table_name, id)
            end)

          {TestSchema, ^id, field, _, _} = result
          assert field == "field"

        _ ->
          assert false
      end

      :mnesia.clear_table(@table_name)
    end

    test "Repo#insert valid record - multiple primary keys" do
      assert {:ok, _} =
               TestRepo.insert(%MultiplePrimaryKeyTestSchema{key1: 1, key2: 1, field: "field 1"})

      assert {:ok, _} =
               TestRepo.insert(%MultiplePrimaryKeyTestSchema{key1: 1, key2: 2, field: "field 2"})

      for i <- [1, 2] do
        ret = :mnesia.dirty_read(@multiple_primary_key_table_name, {1, i})
        assert [{MultiplePrimaryKeyTestSchema, {1, ^i}, 1, ^i, _, _, _}] = ret
      end

      :mnesia.clear_table(@multiple_primary_key_table_name)
    end
  end

  describe "Ecto.Adapters.Schema#insert_all" do
    test "Repo#insert_all valid records" do
      case TestRepo.insert_all(
             TestSchema,
             [%{field: "field 1"}, %{field: "field 2"}],
             returning: [:id]
           ) do
        {count, _records} ->
          assert count == 2

          {:atomic, results} =
            :mnesia.transaction(fn ->
              :mnesia.foldl(fn record, acc -> [record | acc] end, [], @table_name)
            end)

          assert Enum.all?(results, fn
                   {TestSchema, _, "field 1", _, _} -> true
                   {TestSchema, _, "field 2", _, _} -> true
                   _ -> false
                 end)

        _ ->
          assert false
      end

      :mnesia.clear_table(@table_name)
    end

    test "Repo#insert_all valid records - alt record name" do
      case TestRepo.insert_all(
             TestSchemaAltRecord,
             [%{field: "field 1"}, %{field: "field 2"}],
             returning: [:id]
           ) do
        {count, _records} ->
          assert count == 2

          {:atomic, results} =
            :mnesia.transaction(fn ->
              :mnesia.foldl(fn record, acc -> [record | acc] end, [], @alt_record_table_name)
            end)

          assert Enum.all?(results, fn
                   {@alt_record_name, _, "field 1"} -> true
                   {@alt_record_name, _, "field 2"} -> true
                   _ -> false
                 end)

        _ ->
          assert false
      end

      :mnesia.clear_table(@alt_record_table_name)
    end

    test "Repo#insert_all valid records with returning opt" do
      case TestRepo.insert_all(
             TestSchema,
             [%{field: "field 1"}, %{field: "field 2"}],
             returning: [:id]
           ) do
        {count, records} ->
          assert count == 2

          {:atomic, results} =
            :mnesia.transaction(fn ->
              Enum.map(records, fn %{id: id} ->
                :mnesia.read(@table_name, id)
              end)
            end)

          assert Enum.all?(results, fn
                   [{TestSchema, _, "field 1", _, _}] -> true
                   [{TestSchema, _, "field 2", _, _}] -> true
                   _ -> false
                 end)

        _ ->
          assert false
      end

      :mnesia.clear_table(@table_name)
    end

    test "Repo#insert_all valid records with binary ids returning opt" do
      case TestRepo.insert_all(
             BinaryIdTestSchema,
             [%{field: "field 1"}, %{field: "field 2"}],
             returning: [:id, :field]
           ) do
        {count, records} ->
          assert count == 2
          assert length(records) == 2

          {:atomic, results} =
            :mnesia.transaction(fn ->
              :mnesia.foldl(fn record, acc -> [record | acc] end, [], @binary_id_table_name)
            end)

          assert length(results) == 2

        _ ->
          assert false
      end

      :mnesia.clear_table(@binary_id_table_name)
    end

    test "Repo#insert_all valid records without primary key returning opt" do
      case TestRepo.insert_all(
             WithoutPrimaryKeyTestSchema,
             [%{field: "field 1"}, %{field: "field 2"}],
             returning: [:field]
           ) do
        {count, records} ->
          assert count == 2
          assert length(records) == 2

          {:atomic, results} =
            :mnesia.transaction(fn ->
              :mnesia.foldl(
                fn record, acc -> [record | acc] end,
                [],
                @without_primary_key_table_name
              )
            end)

          assert length(results) == 2

        _ ->
          assert false
      end

      :mnesia.clear_table(@without_primary_key_table_name)
    end
  end

  describe "Ecto.Adapters.Schema#update" do
    setup do
      {:atomic, _} =
        :mnesia.transaction(fn ->
          :mnesia.write(@table_name, {TestSchema, 1, "field", nil, nil}, :write)
        end)

      record = TestRepo.get(TestSchema, 1)

      {:ok, record: record}
    end

    test "Repo#update valid record with [on_conflict: :replace_all]", %{record: record} do
      id = record.id
      changeset = TestSchema.changeset(record, %{field: "field updated"})

      ret = TestRepo.update(changeset)
      assert {:ok, %TestSchema{id: ^id, field: "field updated"}} = ret

      ret = :mnesia.transaction(fn -> :mnesia.read(@table_name, id) end)
      assert {:atomic, [{TestSchema, ^id, "field updated", _, _}]} = ret

      :mnesia.clear_table(@table_name)
    end

    test "Repo#update valid record with array field and [on_conflict: :replace_all]" do
      {:atomic, _} =
        :mnesia.transaction(fn ->
          :mnesia.write(@array_table_name, {ArrayTestSchema, 1, ["a", "b"], nil, nil}, :write)
        end)

      record = TestRepo.get(ArrayTestSchema, 1)

      id = record.id
      update = ["c", "d"]
      changeset = ArrayTestSchema.changeset(record, %{field: update})

      case TestRepo.update(changeset) do
        {:ok, %ArrayTestSchema{id: ^id, field: ^update}} ->
          case :mnesia.transaction(fn ->
                 :mnesia.read(@array_table_name, id)
               end) do
            {:atomic, [{ArrayTestSchema, ^id, ^update, _, _}]} -> assert true
            e -> assert false == e
          end

        _ ->
          assert false
      end

      :mnesia.clear_table(@array_table_name)
      :mnesia.clear_table(@table_name)
    end

    test "Repo#update non existing record with [on_conflict: :replace_all]", %{record: record} do
      changeset = TestSchema.changeset(%{record | id: 3}, %{field: "field updated"})

      assert_raise Ecto.StaleEntryError, fn ->
        TestRepo.update(changeset)
      end

      :mnesia.clear_table(@table_name)
    end
  end

  describe "Ecto.Adapters.Schema#update - alt record name" do
    setup do
      {:atomic, _} =
        :mnesia.transaction(fn ->
          :mnesia.write(@alt_record_table_name, {@alt_record_name, 1, "field"}, :write)
        end)

      record = TestRepo.get(TestSchemaAltRecord, 1)

      {:ok, record: record}
    end

    test "Repo#update valid record with [on_conflict: :replace_all]", %{record: record} do
      id = record.id
      changeset = TestSchemaAltRecord.changeset(record, %{field: "field updated"})

      case TestRepo.update(changeset) do
        {:ok, %TestSchemaAltRecord{id: ^id, field: "field updated"}} ->
          case :mnesia.transaction(fn ->
                 :mnesia.read(@alt_record_table_name, id)
               end) do
            {:atomic, [{@alt_record_name, ^id, "field updated"}]} -> assert true
            e -> assert false == e
          end

        _ ->
          assert false
      end

      :mnesia.clear_table(@alt_record_table_name)
    end
  end

  describe "Ecto.Adapters.Schema#delete" do
    setup do
      {:atomic, _} =
        :mnesia.transaction(fn ->
          :mnesia.write(@table_name, {TestSchema, 1, "field", nil, nil}, :write)
        end)

      record = TestRepo.get(TestSchema, 1)
      {:ok, record: record}
    end

    test "Repo#delete an existing record", %{record: record} do
      case TestRepo.delete(record) do
        {:ok, %TestSchema{id: 1, field: "field"}} ->
          case :mnesia.transaction(fn ->
                 :mnesia.read(@table_name, 1)
               end) do
            {:atomic, []} -> assert true
            _ -> assert false
          end

        _ ->
          assert false
      end

      :mnesia.clear_table(@table_name)
    end

    test "Repo#delete a non existing record", %{record: record} do
      assert_raise Ecto.StaleEntryError, fn ->
        TestRepo.delete(%{record | id: 2})
      end

      :mnesia.clear_table(@table_name)
    end
  end
end
