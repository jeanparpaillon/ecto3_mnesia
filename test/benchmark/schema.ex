defmodule Ecto.Adapters.Mnesia.Benchmark.Schema do
  @moduledoc false
  use Ecto.Schema

  alias Ecto.Changeset

  schema "test_table" do
    field(:indexed_int_field, :integer)
    field(:non_indexed_int_field, :integer)
    field(:indexed_field, :string)
    field(:non_indexed_field, :string)

    timestamps()
  end

  def changeset(%__MODULE__{} = struct, params) do
    struct
    |> Changeset.cast(params, [:field])
  end
end
