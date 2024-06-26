defmodule Ecto.Adapters.MnesiaQueryableIntegrationTest do
  use Ecto.Adapters.Mnesia.RepoCase, async: false

  import Ecto.Query, only: [from: 2]

  alias Ecto.Adapters.Mnesia

  @table_name __MODULE__.Table
  @table_name2 __MODULE__.Table2

  defmodule TestType.Charlist do
    use Ecto.Type

    def type, do: :list

    def cast(s), do: {:ok, s}

    def load(cl), do: {:ok, to_string(cl)}

    def dump(s), do: {:ok, to_charlist(s)}
  end

  defmodule TestSchema do
    use Ecto.Schema

    schema "#{Ecto.Adapters.MnesiaQueryableIntegrationTest.Table}" do
      field(:field, :string)
    end

    def __record_name__, do: TestSchema
  end

  defmodule TestSchema2 do
    use Ecto.Schema

    schema "#{Ecto.Adapters.MnesiaQueryableIntegrationTest.Table2}" do
      field(:field, TestType.Charlist)
    end

    def __record_name__, do: TestSchema2
  end

  setup_all do
    [TestSchema, TestSchema2]
    |> Enum.each(fn schema ->
      :ok =
        Mnesia.Migration.sync_create_table(Repo, schema,
          ram_copies: [node()],
          type: :ordered_set
        )
    end)
  end

  describe "Ecto.Adapter.Queryable#execute" do
    test "#all from one table with no query, no records" do
      Repo.transaction(fn ->
        assert Repo.all(TestSchema) == []
      end)
    end

    test "#all from one table with no query, records" do
      records = [
        %TestSchema{id: 1, field: "field 1"},
        %TestSchema{id: 2, field: "field 2"}
      ]

      {:atomic, _result} =
        :mnesia.transaction(fn ->
          Enum.map(records, fn %{id: id, field: field} ->
            :mnesia.write(@table_name, {TestSchema, id, field}, :write)
          end)
        end)

      case Repo.all(TestSchema) do
        [] ->
          assert false

        fetched_records ->
          Enum.map(records, fn %{id: id, field: field} ->
            assert Enum.any?(
                     fetched_records,
                     fn
                       %{id: ^id, field: ^field} -> true
                       _ -> false
                     end
                   )
          end)
      end

      :mnesia.clear_table(@table_name)
    end

    test "#all from one table with basic select query, records" do
      records = [
        %TestSchema{id: 1, field: "field 1"},
        %TestSchema{id: 2, field: "field 2"}
      ]

      {:atomic, _result} =
        :mnesia.transaction(fn ->
          Enum.map(records, fn %{id: id, field: field} ->
            :mnesia.write(@table_name, {TestSchema, id, field}, :write)
          end)
        end)

      assert Repo.all(from(s in TestSchema, select: s.id)) ==
               Enum.map(records, fn %{id: id} -> id end)

      :mnesia.clear_table(@table_name)
    end

    test "#all from one table with multiple field select query, records" do
      records = [
        %TestSchema{id: 1, field: "field 1"},
        %TestSchema{id: 2, field: "field 2"}
      ]

      {:atomic, _result} =
        :mnesia.transaction(fn ->
          Enum.map(records, fn %{id: id, field: field} ->
            :mnesia.write(@table_name, {TestSchema, id, field}, :write)
          end)
        end)

      assert Repo.all(from(s in TestSchema, select: [s.id, s.field])) ==
               Enum.map(records, fn %{id: id, field: field} -> [id, field] end)

      :mnesia.clear_table(@table_name)
    end

    test "#all from one table with simple where query, records" do
      records = [
        %TestSchema{id: 1, field: "field 1"},
        %TestSchema{id: 2, field: "field 2"}
      ]

      {:atomic, _result} =
        :mnesia.transaction(fn ->
          Enum.map(records, fn %{id: id, field: field} ->
            :mnesia.write(@table_name, {TestSchema, id, field}, :write)
          end)
        end)

      case Repo.all(from(s in TestSchema, where: s.id == 1)) do
        [%{id: 1, field: "field 1"}] -> assert true
        e -> assert e == false
      end

      :mnesia.clear_table(@table_name)
    end

    test "#all from one table with simple where query, many records" do
      {:atomic, _result} =
        :mnesia.transaction(fn ->
          Stream.iterate(0, &(&1 + 1))
          |> Enum.take(10_000)
          |> Enum.map(fn id ->
            :mnesia.write(@table_name, {TestSchema, id, "field #{id}"}, :write)
          end)
        end)

      records = Repo.all(from(s in TestSchema, where: s.field == "field 2"))

      assert Enum.all?(records, fn
               %{field: "field 2"} -> true
               _ -> false
             end)

      :mnesia.clear_table(@table_name)
    end

    test "#get_by from one table with simple where query on custom type, many records" do
      {:atomic, _result} =
        :mnesia.transaction(fn ->
          Stream.iterate(0, &(&1 + 1))
          |> Enum.take(10_000)
          |> Enum.map(fn id ->
            :mnesia.write(@table_name2, {TestSchema2, id, ~c"field #{id}"}, :write)
          end)
        end)

      records = Repo.get_by(TestSchema2, field: "field 2")

      assert %{field: "field 2"} = records

      :mnesia.clear_table(@table_name2)
    end

    test "#all from one table with complex (and) where query, records" do
      records = [
        %TestSchema{id: 1, field: "field 1"},
        %TestSchema{id: 2, field: "field 2"}
      ]

      {:atomic, _result} =
        :mnesia.transaction(fn ->
          Enum.map(records, fn %{id: id, field: field} ->
            :mnesia.write(@table_name, {TestSchema, id, field}, :write)
          end)
        end)

      records = Repo.all(from(s in TestSchema, where: s.field == "field 2" and s.id == 2))
      refute Enum.empty?(records)

      assert Enum.all?(records, fn
               %{id: 2, field: "field 2"} -> true
               _ -> false
             end)

      :mnesia.clear_table(@table_name)
    end

    test "#all from one table with complex (or) where query, records" do
      records = [
        %TestSchema{id: 1, field: "field 1"},
        %TestSchema{id: 2, field: "field 2"}
      ]

      {:atomic, _result} =
        :mnesia.transaction(fn ->
          Enum.map(records, fn %{id: id, field: field} ->
            :mnesia.write(@table_name, {TestSchema, id, field}, :write)
          end)
        end)

      records = Repo.all(from(s in TestSchema, where: s.field == "field 2" or s.id == 1))
      refute Enum.empty?(records)

      assert Enum.all?(records, fn
               %{field: "field 2"} -> true
               %{id: 1} -> true
               _ -> false
             end)

      :mnesia.clear_table(@table_name)
    end

    test "#all from one table with complex (mixed and / or) where query, records" do
      records = [
        %TestSchema{id: 1, field: "field 1"},
        %TestSchema{id: 2, field: "field 2"}
      ]

      {:atomic, _result} =
        :mnesia.transaction(fn ->
          Enum.map(records, fn %{id: id, field: field} ->
            :mnesia.write(@table_name, {TestSchema, id, field}, :write)
          end)
        end)

      records =
        Repo.all(
          from(s in TestSchema,
            where: (s.field == "field 2" and s.id == 2) or (s.field == "field 1" and s.id == 1)
          )
        )

      refute Enum.empty?(records)

      assert Enum.all?(records, fn
               %{id: 2, field: "field 2"} -> true
               %{id: 1, field: "field 1"} -> true
               _ -> false
             end)

      :mnesia.clear_table(@table_name)
    end

    test "#all from one table with complex (is_nil) where query, records" do
      records = [
        %TestSchema{id: 1, field: nil},
        %TestSchema{id: 2, field: "field 2"}
      ]

      {:atomic, _result} =
        :mnesia.transaction(fn ->
          Enum.map(records, fn %{id: id, field: field} ->
            :mnesia.write(@table_name, {TestSchema, id, field}, :write)
          end)
        end)

      records = Repo.all(from(s in TestSchema, where: is_nil(s.field)))

      assert Enum.all?(records, fn
               %{field: nil} -> true
               _ -> false
             end)

      :mnesia.clear_table(@table_name)
    end

    test "#all from one table with complex (binding) where query, records" do
      id = 2
      field = "field 2"

      records = [
        %TestSchema{id: 1, field: "field 1"},
        %TestSchema{id: id, field: field}
      ]

      {:atomic, _result} =
        :mnesia.transaction(fn ->
          Enum.map(records, fn %{id: id, field: field} ->
            :mnesia.write(@table_name, {TestSchema, id, field}, :write)
          end)
        end)

      records = Repo.all(from(s in TestSchema, where: s.field == ^field and s.id == ^id))

      assert Enum.all?(records, fn
               %{field: ^field} -> true
               _ -> false
             end)

      :mnesia.clear_table(@table_name)
    end

    test "#all from one table with complex (in) where query, records" do
      records = [
        %TestSchema{id: 1, field: "field 1"},
        %TestSchema{id: 2, field: "field 2"},
        %TestSchema{id: 3, field: "field 3"}
      ]

      {:atomic, _result} =
        :mnesia.transaction(fn ->
          Enum.map(records, fn %{id: id, field: field} ->
            :mnesia.write(@table_name, {TestSchema, id, field}, :write)
          end)
        end)

      case Repo.all(from(s in TestSchema, where: s.id in [1, 3])) do
        [
          %TestSchema{id: 1, field: "field 1"},
          %TestSchema{id: 3, field: "field 3"}
        ] ->
          assert true

        e ->
          assert e == false
      end

      :mnesia.clear_table(@table_name)
    end

    test "#all from one table with complex (!=) where query, records" do
      records = [
        %TestSchema{id: 1, field: "field 1"},
        %TestSchema{id: 2, field: "field 2"},
        %TestSchema{id: 3, field: "field 3"}
      ]

      {:atomic, _result} =
        :mnesia.transaction(fn ->
          Enum.map(records, fn %{id: id, field: field} ->
            :mnesia.write(@table_name, {TestSchema, id, field}, :write)
          end)
        end)

      case Repo.all(from(s in TestSchema, where: s.id != 2)) do
        [
          %TestSchema{id: 1, field: "field 1"},
          %TestSchema{id: 3, field: "field 3"}
        ] ->
          assert true

        e ->
          assert e == false
      end

      :mnesia.clear_table(@table_name)
    end

    test "#all from one table with complex (in / binding) where query, records" do
      records = [
        %TestSchema{id: 1, field: "field 1"},
        %TestSchema{id: 2, field: "field 2"},
        %TestSchema{id: 3, field: "field 3"}
      ]

      {:atomic, _result} =
        :mnesia.transaction(fn ->
          Enum.map(records, fn %{id: id, field: field} ->
            :mnesia.write(@table_name, {TestSchema, id, field}, :write)
          end)
        end)

      ids = [1, 3]
      id = 1

      case Repo.all(from(s in TestSchema, where: s.id == ^id or s.id in ^ids)) do
        [
          %TestSchema{id: 1, field: "field 1"},
          %TestSchema{id: 3, field: "field 3"}
        ] ->
          assert true

        e ->
          assert e == false
      end

      :mnesia.clear_table(@table_name)
    end

    test "#all from one table with negation where query, records" do
      records = [
        %TestSchema{id: 1, field: nil},
        %TestSchema{id: 2, field: "field 2"}
      ]

      {:atomic, _result} =
        :mnesia.transaction(fn ->
          Enum.map(records, fn %{id: id, field: field} ->
            :mnesia.write(@table_name, {TestSchema, id, field}, :write)
          end)
        end)

      assert [record] = Repo.all(from(s in TestSchema, where: not is_nil(s.field)))
      assert record.id == 2

      assert [record] = Repo.all(from(s in TestSchema, where: s.id not in ^[2, 3]))
      assert record.id == 1

      :mnesia.clear_table(@table_name)
    end

    test "#update_all from one table with simple where query, records" do
      records = [
        %TestSchema{id: 1, field: "field 1"},
        %TestSchema{id: 2, field: "field 2"},
        %TestSchema{id: 3, field: "field 3"}
      ]

      {:atomic, _result} =
        :mnesia.transaction(fn ->
          Enum.map(records, fn %{id: id, field: field} ->
            :mnesia.write(@table_name, {TestSchema, id, field}, :write)
          end)
        end)

      {count, records} =
        Repo.update_all(
          from(s in TestSchema, where: s.id == 1 or s.id == 2),
          set: [field: "updated field"]
        )

      assert 2 == count

      assert Enum.all?(records, fn
               %{field: "updated field"} -> true
               _ -> false
             end)

      :mnesia.clear_table(@table_name)
    end

    test "#delete_all from one table, records" do
      records = [
        %TestSchema{id: 1, field: "field 1"},
        %TestSchema{id: 2, field: "field 2"},
        %TestSchema{id: 3, field: "field 3"}
      ]

      {:atomic, _result} =
        :mnesia.transaction(fn ->
          Enum.map(records, fn %{id: id, field: field} ->
            :mnesia.write(@table_name, {TestSchema, id, field}, :write)
          end)
        end)

      {count, nil} = Repo.delete_all(TestSchema)
      assert count == 3

      :mnesia.clear_table(@table_name)
    end

    test "#delete_all from one table select with primary key query, records" do
      records = [
        %TestSchema{id: 1, field: "field 1"},
        %TestSchema{id: 2, field: "field 2"},
        %TestSchema{id: 3, field: "field 3"}
      ]

      {:atomic, _result} =
        :mnesia.transaction(fn ->
          Enum.map(records, fn %{id: id, field: field} ->
            :mnesia.write(@table_name, {TestSchema, id, field}, :write)
          end)
        end)

      ret = Repo.delete_all(from(t in TestSchema, select: t.id))
      assert {3, [1, 2, 3]} = ret

      for i <- 1..3 do
        assert [] = :mnesia.dirty_read(@table_name, i)
      end

      :mnesia.clear_table(@table_name)
    end

    test "#delete_all from one table with simple where query, records" do
      records = [
        %TestSchema{id: 1, field: "field 1"},
        %TestSchema{id: 2, field: "field 2"},
        %TestSchema{id: 3, field: "field 3"}
      ]

      {:atomic, _result} =
        :mnesia.transaction(fn ->
          Enum.map(records, fn %{id: id, field: field} ->
            :mnesia.write(@table_name, {TestSchema, id, field}, :write)
          end)
        end)

      assert {2, nil} = Repo.delete_all(from(s in TestSchema, where: s.id == 1 or s.id == 2))

      assert {:atomic, [{_, 3, "field 3"}]} =
               :mnesia.transaction(fn ->
                 :mnesia.foldl(fn record, acc -> [record | acc] end, [], @table_name)
               end)

      :mnesia.clear_table(@table_name)
    end

    test "#all from one table with simple sort query, records" do
      records = [
        %TestSchema{id: 1, field: "field 2"},
        %TestSchema{id: 2, field: "field 3"},
        %TestSchema{id: 3, field: "field 1"}
      ]

      {:atomic, _result} =
        :mnesia.transaction(fn ->
          Enum.map(records, fn %{id: id, field: field} ->
            :mnesia.write(@table_name, {TestSchema, id, field}, :write)
          end)
        end)

      ret = Repo.all(from(s in TestSchema, order_by: [desc: :field]))

      assert [%{id: 2, field: "field 3"}, %{id: 1, field: "field 2"}, %{id: 3, field: "field 1"}] =
               ret

      :mnesia.clear_table(@table_name)
    end

    # NOTE not supported by the adapter yet need to explore the possibility of qlc sort function
    @tag :skip
    test "#all from one table with complex sort (multiple fields) query, records" do
      records = [
        %TestSchema{id: 1, field: "field 2"},
        %TestSchema{id: 2, field: "field 2"},
        %TestSchema{id: 3, field: "field 1"}
      ]

      {:atomic, _result} =
        :mnesia.transaction(fn ->
          Enum.map(records, fn %{id: id, field: field} ->
            :mnesia.write(@table_name, {TestSchema, id, field}, :write)
          end)
        end)

      assert [%{id: 2, field: "field 2"}, %{id: 1, field: "field 2"}, %{id: 3, field: "field 2"}] =
               Repo.all(from(s in TestSchema, order_by: [desc: :id, desc: :field]))

      :mnesia.clear_table(@table_name)
    end

    test "#all from one table with simple limit query, records" do
      records = [
        %TestSchema{id: 1, field: "field 1"},
        %TestSchema{id: 2, field: "field 2"},
        %TestSchema{id: 3, field: "field 3"}
      ]

      {:atomic, _result} =
        :mnesia.transaction(fn ->
          Enum.map(records, fn %{id: id, field: field} ->
            :mnesia.write(@table_name, {TestSchema, id, field}, :write)
          end)
        end)

      assert [%{id: 1, field: "field 1"}, %{id: 2, field: "field 2"}] =
               Repo.all(from(s in TestSchema, limit: 2))

      :mnesia.clear_table(@table_name)
    end

    test "#all from one table with limit query (binding), records" do
      records = [
        %TestSchema{id: 1, field: "field 1"},
        %TestSchema{id: 2, field: "field 2"},
        %TestSchema{id: 3, field: "field 3"}
      ]

      {:atomic, _result} =
        :mnesia.transaction(fn ->
          Enum.map(records, fn %{id: id, field: field} ->
            :mnesia.write(@table_name, {TestSchema, id, field}, :write)
          end)
        end)

      limit = 2

      assert [%{id: 1, field: "field 1"}, %{id: 2, field: "field 2"}] =
               Repo.all(from(s in TestSchema, limit: ^limit))

      :mnesia.clear_table(@table_name)
    end

    test "#all from one table with simple offset query, records" do
      records = [
        %TestSchema{id: 1, field: "field 1"},
        %TestSchema{id: 2, field: "field 2"},
        %TestSchema{id: 3, field: "field 3"}
      ]

      {:atomic, _result} =
        :mnesia.transaction(fn ->
          Enum.map(records, fn %{id: id, field: field} ->
            :mnesia.write(@table_name, {TestSchema, id, field}, :write)
          end)
        end)

      assert [%{id: 3, field: "field 3"}] = Repo.all(from(s in TestSchema, offset: 2))

      :mnesia.clear_table(@table_name)
    end

    test "#all from one table with offset query (binding), records" do
      records = [
        %TestSchema{id: 1, field: "field 1"},
        %TestSchema{id: 2, field: "field 2"},
        %TestSchema{id: 3, field: "field 3"}
      ]

      {:atomic, _result} =
        :mnesia.transaction(fn ->
          Enum.map(records, fn %{id: id, field: field} ->
            :mnesia.write(@table_name, {TestSchema, id, field}, :write)
          end)
        end)

      offset = 2
      assert [%{id: 3, field: "field 3"}] = Repo.all(from(s in TestSchema, offset: ^offset))

      :mnesia.clear_table(@table_name)
    end

    test "#all from one table with limit and offset query, records" do
      records = [
        %TestSchema{id: 1, field: "field 1"},
        %TestSchema{id: 2, field: "field 2"},
        %TestSchema{id: 3, field: "field 3"}
      ]

      {:atomic, _result} =
        :mnesia.transaction(fn ->
          Enum.map(records, fn %{id: id, field: field} ->
            :mnesia.write(@table_name, {TestSchema, id, field}, :write)
          end)
        end)

      assert [%{id: 2, field: "field 2"}] =
               Repo.all(from(s in TestSchema, limit: 1, offset: 1))

      :mnesia.clear_table(@table_name)
    end

    test "Repo.get" do
      records = [
        %TestSchema{id: 1, field: "field 1"},
        %TestSchema{id: 2, field: "field 2"},
        %TestSchema{id: 3, field: "field 3"}
      ]

      {:atomic, _result} =
        :mnesia.transaction(fn ->
          Enum.map(records, fn %{id: id, field: field} ->
            :mnesia.write(@table_name, {TestSchema, id, field}, :write)
          end)
        end)

      assert %TestSchema{id: 1, field: "field 1"} = Repo.get(TestSchema, 1)

      :mnesia.clear_table(@table_name)
    end
  end
end
