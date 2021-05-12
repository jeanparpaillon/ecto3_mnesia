defmodule Ecto.Adapters.Mnesia.Source do
  @moduledoc false
  defstruct table: nil,
            schema: nil,
            loaded: nil,
            info: nil,
            autogenerate_id: nil

  @type t :: %__MODULE__{}

  def new({table, schema, _prefix}) do
    new(%{source: table, schema: schema})
  end

  def new(schema_meta) do
    table = String.to_atom(schema_meta.source)
    schema = schema_meta.schema

    %__MODULE__{
      table: table,
      schema: schema,
      loaded: apply(schema, :__schema__, [:loaded]),
      info: table |> :mnesia.table_info(:all) |> Map.new(),
      autogenerate_id: schema_meta[:autogenerate_id]
    }
  end
end
