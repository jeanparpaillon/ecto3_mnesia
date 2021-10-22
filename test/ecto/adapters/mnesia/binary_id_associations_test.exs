defmodule Ecto.Adapters.MnesiaBinaryAssociationsIntegrationTest do
  use Ecto.Adapters.Mnesia.RepoCase, async: false

  alias EctoMnesia.TestRepo
  alias Ecto.Adapters.Mnesia

  @has_many_table_name __MODULE__.HasMany
  @belongs_to_table_name __MODULE__.BelongsTo
  @many_to_many_a_table_name __MODULE__.ManyToManyA
  @many_to_many_b_table_name __MODULE__.ManyToManyB
  @join_table_name __MODULE__.JoinTable

  defmodule BelongsToSchema do
    use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
    schema "#{Ecto.Adapters.MnesiaBinaryAssociationsIntegrationTest.BelongsTo}" do
      field(:field, :string)

      belongs_to(:has_many, Ecto.Adapters.MnesiaBinaryAssociationsIntegrationTest.HasManySchema)
    end
  end

  defmodule HasManySchema do
    use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
    schema "#{Ecto.Adapters.MnesiaBinaryAssociationsIntegrationTest.HasMany}" do
      field(:field, :string)

      has_many(:belongs_tos, Ecto.Adapters.MnesiaBinaryAssociationsIntegrationTest.BelongsToSchema,
        foreign_key: :has_many_id
      )
    end
  end

  defmodule ManyToManySchemaA do
    use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
    schema "#{Ecto.Adapters.MnesiaBinaryAssociationsIntegrationTest.ManyToManyA}" do
      field(:field, :string)

      many_to_many(
        :many_to_many_bs,
        Ecto.Adapters.MnesiaBinaryAssociationsIntegrationTest.ManyToManySchemaB,
        join_through: "#{Ecto.Adapters.MnesiaBinaryAssociationsIntegrationTest.JoinTable}",
        join_keys: [{:a_id, :id}, {:b_id, :id}]
      )
    end
  end

  defmodule ManyToManySchemaB do
    use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
    schema "#{Ecto.Adapters.MnesiaBinaryAssociationsIntegrationTest.ManyToManyB}" do
      field(:field, :string)

      many_to_many(
        :many_to_many_as,
        Ecto.Adapters.MnesiaBinaryAssociationsIntegrationTest.ManyToManySchemaA,
        join_through: "#{Ecto.Adapters.MnesiaBinaryAssociationsIntegrationTest.JoinTable}"
      )
    end
  end

  setup_all do
    [BelongsToSchema, HasManySchema, ManyToManySchemaA, ManyToManySchemaB]
    |> Enum.each(fn schema ->
      :ok = Mnesia.Migration.sync_create_table(TestRepo, schema, ram_copies: [node()])
    end)
  end

  test "preload has_many association" do
    a = Ecto.UUID.generate()
    b = Ecto.UUID.generate()
    :mnesia.transaction(fn ->
      :mnesia.write(@has_many_table_name, {HasManySchema, a, "has many"}, :write)
      :mnesia.write(@has_many_table_name, {HasManySchema, b, "has many"}, :write)
      :mnesia.write(@belongs_to_table_name, {BelongsToSchema, a, "belongs to", a}, :write)
      :mnesia.write(@belongs_to_table_name, {BelongsToSchema, b, "belongs to", a}, :write)
    end)

    assert %HasManySchema{belongs_tos: belongs_tos} = TestRepo.get(HasManySchema, a) |> TestRepo.preload(:belongs_tos)

    [TestRepo.get(BelongsToSchema, a), TestRepo.get(BelongsToSchema, b)]
    |> Enum.map(fn belongs_to ->
      assert Enum.member?(belongs_tos, belongs_to)
    end)
    assert length(belongs_tos) == 2
    :mnesia.clear_table(@has_many_table_name)
    :mnesia.clear_table(@belongs_to_table_name)
  end

  test "preload belongs_to association" do
    a = Ecto.UUID.generate()
    b = Ecto.UUID.generate()
    :mnesia.transaction(fn ->
      :mnesia.write(@has_many_table_name, {HasManySchema, a, "has many"}, :write)
      :mnesia.write(@has_many_table_name, {HasManySchema, b, "has many"}, :write)
      :mnesia.write(@belongs_to_table_name, {BelongsToSchema, a, "belongs to", a}, :write)
      :mnesia.write(@belongs_to_table_name, {BelongsToSchema, b, "belongs to", a}, :write)
    end)

    case TestRepo.get(BelongsToSchema, a) |> TestRepo.preload(:has_many) do
      %BelongsToSchema{has_many: has_many} ->
        assert has_many == TestRepo.get(HasManySchema, a)

      _ ->
        assert false
    end

    :mnesia.clear_table(@has_many_table_name)
    :mnesia.clear_table(@belongs_to_table_name)
  end

  @tag :skip
  # NOTE this adapter do not support many to many relationships
  test "preload many_to_many association" do
    a = Ecto.UUID.generate()
    b = Ecto.UUID.generate()
    :mnesia.transaction(fn ->
      :mnesia.write(@many_to_many_a_table_name, {ManyToManySchemaA, a, "many to many A"}, :write)
      :mnesia.write(@many_to_many_a_table_name, {ManyToManySchemaA, b, "many to many A"}, :write)
      :mnesia.write(@many_to_many_b_table_name, {ManyToManySchemaB, a, "many to many B"}, :write)
      :mnesia.write(@many_to_many_b_table_name, {ManyToManySchemaB, b, "many to many B"}, :write)
      :mnesia.write(@join_table_name, {@join_table_name, a, a}, :write)
      :mnesia.write(@join_table_name, {@join_table_name, a, b}, :write)
      :mnesia.write(@join_table_name, {@join_table_name, b, a}, :write)
    end)

    case TestRepo.get(ManyToManySchemaA, a) |> TestRepo.preload(:many_to_many_bs) do
      %ManyToManySchemaA{many_to_many_bs: many_to_many_bs} ->
        assert many_to_many_bs == [
                 TestRepo.get(ManyToManySchemaB, a),
                 TestRepo.get(ManyToManySchemaB, 2)
               ]

      e ->
        assert false == e
    end
  end
end
