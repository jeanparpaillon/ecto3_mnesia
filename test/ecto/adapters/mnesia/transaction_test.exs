defmodule Ecto.Adapters.MnesiaTransactionIntegrationTest do
  use Ecto.Adapters.Mnesia.RepoCase, async: false

  alias Ecto.Adapters.Mnesia
  alias Ecto.Changeset
  alias Ecto.Multi

  defmodule TestSchema do
    use Ecto.Schema

    schema "#{Ecto.Adapters.MnesiaTransactionIntegrationTest.Table}" do
      field(:field, :string)
    end

    def changeset(params) do
      %__MODULE__{}
      |> Ecto.Changeset.cast(Map.new(params), [:id, :field])
      |> Ecto.Changeset.unique_constraint(:id)
    end
  end

  setup_all do
    :ok = Mnesia.Migration.drop_table(Repo, TestSchema)

    :ok =
      Mnesia.Migration.sync_create_table(Repo, TestSchema,
        ram_copies: [node()],
        type: :ordered_set
      )

    :ok
  end

  describe "Ecto.Adapter.Transaction" do
    test "#transaction should execute" do
      assert {:ok, _} =
               Repo.transaction(fn ->
                 Repo.all(TestSchema)
               end)
    end

    test "#rollback should rollback" do
      assert Repo.transaction(fn ->
               Repo.rollback(:reason)
             end) == {:error, :reason}
    end

    test "#in_transaction should return false" do
      assert Repo.in_transaction?() == false
    end

    test "#in_transaction should return true in transaction" do
      Repo.transaction(fn ->
        assert Repo.in_transaction?() == false
      end)
    end
  end

  describe "Ecto.Multi" do
    test "Rollback when insert conflict" do
      ret =
        Multi.new()
        |> Multi.insert(:rec1, TestSchema.changeset([]))
        |> Multi.insert(
          :rec2,
          fn %{rec1: %{id: id}} ->
            TestSchema.changeset(id: id)
          end,
          on_conflict: :raise
        )
        |> Repo.transaction()

      assert {:error, :rec2, %Changeset{errors: [id: {"has already been taken", _}]}, %{rec1: _}} =
               ret
    end

    test "in parallel - ensure no cyclic locks" do
      insert = fn i ->
        Multi.new()
        |> Multi.run(:all, fn repo, _ ->
          {:ok, repo.all(TestSchema)}
        end)
        |> Multi.insert(:write, TestSchema.changeset(field: "#{i}"))
        |> Multi.run(:read, fn repo, %{write: %{id: j}} ->
          {:ok, repo.get(TestSchema, j)}
        end)
        |> Repo.transaction()
      end

      1..100
      |> Enum.map(&Task.async(fn -> insert.(&1) end))
      |> Enum.map(&Task.await/1)
      |> Enum.each(fn ret ->
        assert {:ok, _} = ret
      end)
    end
  end
end
