defmodule Ecto.Adapters.Mnesia.Source do
  @moduledoc false
  defstruct table: nil,
            schema: nil,
            loaded: nil,
            info: nil,
            autogenerate_id: nil,
            index: %{},
            schema_erl_prefix: nil

  @type t :: %__MODULE__{}

  def new({table, schema, _prefix}) do
    new(%{source: table, schema: schema})
  end

  def new(schema_meta) do
    table = String.to_atom(schema_meta.source)
    schema = schema_meta.schema
    table_info = table |> :mnesia.table_info(:all) |> Map.new()

    index =
      table_info.attributes
      |> Enum.with_index()
      |> Enum.reduce(%{}, fn {a, i}, acc ->
        Map.put(acc, a, i + 1)
      end)

    schema_erl_prefix = schema |> to_string() |> String.replace(".", "_")

    %__MODULE__{
      table: table,
      schema: schema,
      loaded: apply(schema, :__schema__, [:loaded]),
      info: table_info,
      autogenerate_id: schema_meta[:autogenerate_id],
      index: index,
      schema_erl_prefix: schema_erl_prefix
    }
  end
end
