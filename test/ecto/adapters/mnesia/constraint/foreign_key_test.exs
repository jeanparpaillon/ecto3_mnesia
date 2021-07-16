defmodule Ecto.Adapters.Mnesia.Constraint.ForeignKeyTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.Mnesia.Constraint.ForeignKey

  defmodule BaseSchema do
    use Ecto.Schema

    schema "base" do
      field(:field, :string)

      timestamps()
    end
  end

  defmodule RefSchema do
    use Ecto.Schema

    schema "ref" do
      field(:field, :string)
      belongs_to(:parent, BaseSchema)
    end
  end

  test ".references/2 - defaults" do
    ret = ForeignKey.new({:ref, :parent_id}, :base)

    assert %ForeignKey{
             name: "ref_parent_id_fkey",
             from: {:ref, [:parent_id]},
             to: {:base, [:id]},
             type: :id,
             errors: []
           } = ret
  end

  test ".references/2 - name opt" do
    ret = ForeignKey.new({:ref, :parent_id}, :base, name: "custom_fkey")

    assert %ForeignKey{
             name: "custom_fkey",
             from: {:ref, [:parent_id]},
             to: {:base, [:id]},
             type: :id,
             errors: []
           } = ret
  end
end
