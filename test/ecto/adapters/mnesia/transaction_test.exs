defmodule Ecto.Adapters.MnesiaTransactionIntegrationTest do
  use ExUnit.Case, async: false

  alias EctoMnesia.TestRepo
  alias Ecto.Adapters.Mnesia
  alias Ecto.Changeset
  alias Ecto.Multi

  @table_name __MODULE__.Table

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
    ExUnit.CaptureLog.capture_log(fn -> Mnesia.storage_up(nodes: [node()]) end)
    Mnesia.ensure_all_started([], :permanent)
    {:ok, _repo} = TestRepo.start_link()

    :mnesia.create_table(@table_name,
      ram_copies: [node()],
      record_name: TestSchema,
      attributes: [:id, :field],
      storage_properties: [
        ets: [:compressed]
      ],
      type: :ordered_set
    )

    :mnesia.wait_for_tables([@table_name], 1000)
  end

  describe "Ecto.Adapter.Transaction" do
    test "#transaction should execute" do
      assert TestRepo.transaction(fn ->
               TestRepo.all(TestSchema)
             end) == {:ok, []}
    end

    test "#rollback should rollback" do
      assert TestRepo.transaction(fn ->
               TestRepo.rollback(:reason)
             end) == {:error, :reason}
    end

    test "#in_transaction should return false" do
      assert TestRepo.in_transaction?() == false
    end

    test "#in_transaction should return true in transaction" do
      TestRepo.transaction(fn ->
        assert TestRepo.in_transaction?() == false
      end)
    end
  end

  describe "Ecto.Multi" do
    test "Rollback when insert conflict" do
      changeset = TestSchema.changeset(id: 1)

      ret =
        Multi.new()
        |> Multi.insert(:rec1, changeset)
        |> Multi.insert(:rec2, changeset, on_conflict: :raise)
        |> TestRepo.transaction()

      assert {:error, :rec2, %Changeset{errors: [id: {"has already been taken", _}]}, %{rec1: _}} = ret
    end
  end
end
