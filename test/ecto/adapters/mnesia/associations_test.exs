defmodule Ecto.Adapters.MnesiaAssociationsIntegrationTest do
  use Ecto.Adapters.Mnesia.RepoCase, async: false

  alias Ecto.Adapters.Mnesia
  alias EctoMnesia.TestRepo

  @has_many_table_name __MODULE__.HasMany
  @belongs_to_table_name __MODULE__.BelongsTo
  @many_to_many_a_table_name __MODULE__.ManyToManyA
  @many_to_many_b_table_name __MODULE__.ManyToManyB
  @join_table_name __MODULE__.JoinTable

  defmodule BelongsToSchema do
    use Ecto.Schema

    schema "#{Ecto.Adapters.MnesiaAssociationsIntegrationTest.BelongsTo}" do
      field(:field, :string)

      belongs_to(:has_many, Ecto.Adapters.MnesiaAssociationsIntegrationTest.HasManySchema)
    end
  end

  defmodule HasManySchema do
    use Ecto.Schema

    schema "#{Ecto.Adapters.MnesiaAssociationsIntegrationTest.HasMany}" do
      field(:field, :string)

      has_many(:belongs_tos, Ecto.Adapters.MnesiaAssociationsIntegrationTest.BelongsToSchema,
        foreign_key: :has_many_id
      )
    end
  end

  defmodule ManyToManySchemaA do
    use Ecto.Schema

    schema "#{Ecto.Adapters.MnesiaAssociationsIntegrationTest.ManyToManyA}" do
      field(:field, :string)

      many_to_many(
        :many_to_many_bs,
        Ecto.Adapters.MnesiaAssociationsIntegrationTest.ManyToManySchemaB,
        join_through: "#{Ecto.Adapters.MnesiaAssociationsIntegrationTest.JoinTable}",
        join_keys: [{:a_id, :id}, {:b_id, :id}]
      )
    end
  end

  defmodule ManyToManySchemaB do
    use Ecto.Schema

    schema "#{Ecto.Adapters.MnesiaAssociationsIntegrationTest.ManyToManyB}" do
      field(:field, :string)

      many_to_many(
        :many_to_many_as,
        Ecto.Adapters.MnesiaAssociationsIntegrationTest.ManyToManySchemaA,
        join_through: "#{Ecto.Adapters.MnesiaAssociationsIntegrationTest.JoinTable}"
      )
    end
  end

  setup_all do
    [BelongsToSchema, HasManySchema, ManyToManySchemaA, ManyToManySchemaB]
    |> Enum.each(fn schema ->
      :ok = Mnesia.Migration.sync_create_table(TestRepo, schema, ram_copies: [node()])
    end)

    []
  end

  test "preload has_many association" do
    :mnesia.transaction(fn ->
      :mnesia.write(@has_many_table_name, {HasManySchema, 1, "has many"}, :write)
      :mnesia.write(@has_many_table_name, {HasManySchema, 2, "has many"}, :write)
      :mnesia.write(@belongs_to_table_name, {BelongsToSchema, 1, "belongs to", 1}, :write)
      :mnesia.write(@belongs_to_table_name, {BelongsToSchema, 2, "belongs to", 1}, :write)
    end)

    case TestRepo.get(HasManySchema, 1) |> TestRepo.preload(:belongs_tos) do
      %HasManySchema{belongs_tos: belongs_tos} ->
        assert belongs_tos == [TestRepo.get(BelongsToSchema, 1), TestRepo.get(BelongsToSchema, 2)]

      _ ->
        assert false
    end
  end

  test "preload belongs_to association" do
    :mnesia.transaction(fn ->
      :mnesia.write(@has_many_table_name, {HasManySchema, 1, "has many"}, :write)
      :mnesia.write(@has_many_table_name, {HasManySchema, 2, "has many"}, :write)
      :mnesia.write(@belongs_to_table_name, {BelongsToSchema, 1, "belongs to", 1}, :write)
      :mnesia.write(@belongs_to_table_name, {BelongsToSchema, 2, "belongs to", 1}, :write)
    end)

    case TestRepo.get(BelongsToSchema, 1) |> TestRepo.preload(:has_many) do
      %BelongsToSchema{has_many: has_many} ->
        assert has_many == TestRepo.get(HasManySchema, 1)

      _ ->
        assert false
    end
  end

  @tag :skip
  # NOTE this adapter do not support many to many relationships
  test "preload many_to_many association" do
    :mnesia.transaction(fn ->
      :mnesia.write(@many_to_many_a_table_name, {ManyToManySchemaA, 1, "many to many A"}, :write)
      :mnesia.write(@many_to_many_a_table_name, {ManyToManySchemaA, 2, "many to many A"}, :write)
      :mnesia.write(@many_to_many_b_table_name, {ManyToManySchemaB, 1, "many to many B"}, :write)
      :mnesia.write(@many_to_many_b_table_name, {ManyToManySchemaB, 2, "many to many B"}, :write)
      :mnesia.write(@join_table_name, {@join_table_name, 1, 1}, :write)
      :mnesia.write(@join_table_name, {@join_table_name, 1, 2}, :write)
      :mnesia.write(@join_table_name, {@join_table_name, 2, 1}, :write)
    end)

    case TestRepo.get(ManyToManySchemaA, 1) |> TestRepo.preload(:many_to_many_bs) do
      %ManyToManySchemaA{many_to_many_bs: many_to_many_bs} ->
        assert many_to_many_bs == [
                 TestRepo.get(ManyToManySchemaB, 1),
                 TestRepo.get(ManyToManySchemaB, 2)
               ]

      e ->
        assert false == e
    end
  end
end
