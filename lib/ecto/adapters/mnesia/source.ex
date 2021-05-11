defmodule Ecto.Adapters.Mnesia.Source do
  @moduledoc false
  defstruct table: nil,
            schema: nil,
            loaded: nil,
            info: nil,
            autogenerate_id: nil,
            adapter_meta: nil

  @type t :: %__MODULE__{}

  def new({table, schema, _prefix}) do
    table = String.to_atom(table)

    %__MODULE__{
      table: table,
      schema: schema,
      loaded: apply(schema, :__schema__, [:loaded]),
      info: table |> :mnesia.table_info(:all) |> Map.new()
    }
  end

  def new(schema_meta, adapter_meta) do
    table = String.to_atom(schema_meta.source)
    schema = schema_meta.schema

    %__MODULE__{
      table: table,
      schema: schema,
      loaded: apply(schema, :__schema__, [:loaded]),
      info: :mnesia.table_info(table, :all),
      autogenerate_id: schema_meta.autogenerate_id,
      adapter_meta: adapter_meta
    }
  end
end
