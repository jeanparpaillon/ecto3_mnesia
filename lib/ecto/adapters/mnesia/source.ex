defmodule Ecto.Adapters.Mnesia.Source do
  @moduledoc false
  defstruct table: nil,
            schema: nil,
            loaded: nil,
            autogenerate_id: nil,
            index: %{},
            schema_erl_prefix: nil,
            record_name: nil,
            wild_pattern: nil,
            attributes: []

  @type t :: %__MODULE__{}

  def new({table, schema, _prefix}) do
    new(%{source: table, schema: schema})
  end

  def new(schema_meta) do
    table = String.to_atom(schema_meta.source)
    schema = schema_meta.schema

    record_name = record_name(schema)

    attributes =
      case schema.__schema__(:primary_key) do
        [] ->
          schema_sources(schema)

        [_] ->
          schema_sources(schema)

        [_, _ | _] ->
          [:__key__ | schema_sources(schema)]
      end

    wild_pattern = :_ |> Tuple.duplicate(length(attributes)) |> Tuple.insert_at(0, record_name)

    index =
      attributes
      |> Enum.with_index()
      |> Enum.reduce(%{}, fn {a, i}, acc ->
        Map.put(acc, a, i + 1)
      end)

    schema_erl_prefix = schema |> to_string() |> String.replace(".", "_")

    %__MODULE__{
      table: table,
      schema: schema,
      loaded: apply(schema, :__schema__, [:loaded]),
      autogenerate_id: schema_meta[:autogenerate_id],
      index: index,
      schema_erl_prefix: schema_erl_prefix,
      record_name: record_name,
      wild_pattern: wild_pattern,
      attributes: attributes
    }
  end

  @doc false
  def attributes(%{attributes: attributes}) do
    attributes
  end

  @doc false
  def fields(%{schema: schema}) do
    schema.__schema__(:fields)
  end

  @doc false
  @spec uniques(t(), Keyword.t()) :: [{atom(), term()}]
  def uniques(%{schema: schema}, params) do
    keys = schema.__schema__(:primary_key)

    keys
    |> Enum.reduce([], fn key, acc ->
      case Keyword.fetch(params, key) do
        {:ok, value} -> [{key, value} | acc]
        :error -> acc
      end
    end)
  end

  @doc false
  def qlc_attributes_pattern(source) do
    source.attributes
    |> Enum.map(fn attribute -> to_erl_var(source, attribute) end)
  end

  @doc false
  def qlc_record_pattern(%{schema_erl_prefix: prefix} = source) do
    [prefix | qlc_attributes_pattern(source)]
  end

  @doc false
  def to_erl_var(%{schema_erl_prefix: prefix}, attribute) do
    prefix <> "_" <> (attribute |> to_string() |> String.capitalize())
  end

  ###
  ### Priv
  ###
  defp record_name(schema) do
    if function_exported?(schema, :__record_name__, 0) do
      apply(schema, :__record_name__, [])
    else
      schema
    end
  end

  defp schema_sources(schema) do
    schema
    |> apply(:__schema__, [:fields])
    |> Enum.map(&schema.__schema__(:field_source, &1))
  end
end
