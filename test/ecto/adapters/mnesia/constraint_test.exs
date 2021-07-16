defmodule Ecto.Adapters.Mnesia.ConstraintTest do
  use Ecto.Adapters.Mnesia.RepoCase, async: false

  alias EctoMnesia.TestRepo, as: Repo
  alias Ecto.Adapters.Mnesia

  defmodule ParentSchema do
    use Ecto.Schema

    import Ecto.Changeset

    schema "#{Ecto.Adapters.Mnesia.ConstraintTest.ParentSchema}" do
      field(:field, :string)
    end

    def changeset(s \\ %__MODULE__{}, params) do
      cast(s, params, [:id, :field])
    end
  end

  defmodule ChildSchema do
    use Ecto.Schema

    import Ecto.Changeset

    schema "#{Ecto.Adapters.Mnesia.ConstraintTest.ChildSchema}" do
      field(:field, :string)
      belongs_to(:parent, Ecto.Adapters.Mnesia.ConstraintTest.ParentSchema)
    end

    def changeset(s \\ %__MODULE__{}, params) do
      s
      |> cast(params, [:id, :field, :parent_id])
      |> cast_assoc(:parent)
      |> foreign_key_constraint(:parent_id)
    end
  end

  setup_all do
    :ok = Mnesia.Migration.sync_create_table(ParentSchema)
    :ok = Mnesia.Migration.sync_create_table(ChildSchema)
    :ok = Mnesia.Migration.references(ChildSchema, :parent)

    :ok
  end

  test "insert - valid foreign key" do
    parent = Repo.insert!(%ParentSchema{field: "one"})

    ret =
      %{field: "two", parent_id: parent.id}
      |> ChildSchema.changeset()

    assert ret.valid?
    assert {:ok, _} = Repo.insert(ret)
  end

  test "insert - invalid foreign key" do
    ret =
      %{field: "three", parent_id: -1}
      |> ChildSchema.changeset()

    assert ret.valid?
    assert {:error, _} = Repo.insert(ret)
  end

  test "insert - no foreign key" do
    ret = ChildSchema.changeset(%{field: "three"})

    assert ret.valid?
    assert {:ok, _} = Repo.insert(ret)
  end

  test "update - invalid foreign key" do
    parent = Repo.insert!(%ParentSchema{field: "one"})

    child =
      %{field: "two", parent_id: parent.id}
      |> ChildSchema.changeset()
      |> Repo.insert!()

    ret = ChildSchema.changeset(child, %{parent_id: -1})
    assert ret.valid?

    ret = Repo.update(ret)
    assert {:error, _} = ret
  end
end
