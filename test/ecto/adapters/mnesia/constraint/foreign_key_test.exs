defmodule Ecto.Adapters.Mnesia.Constraint.ForeignKeyTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.Mnesia.Constraint.ForeignKey
  alias Ecto.Adapters.Mnesia.Source

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
    ret = ForeignKey.new(Source.new(%{schema: RefSchema}), :parent)

    assert %ForeignKey{
             name: "ref_parent_id_fkey",
             from: %Source{table: :ref},
             to: %Source{table: :base},
             errors: []
           } = ret
  end

  test ".references/2 - name opt" do
    ret = ForeignKey.new(Source.new(%{schema: RefSchema}), :parent, name: "custom_fkey")

    assert %ForeignKey{
             name: "custom_fkey",
             from: %Source{table: :ref},
             to: %Source{table: :base},
             errors: []
           } = ret
  end
end
