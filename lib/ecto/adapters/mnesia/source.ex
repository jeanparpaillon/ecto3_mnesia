defmodule Ecto.Adapters.Mnesia.Source do
  @moduledoc false
  defstruct table: nil,
            schema: nil,
            loaded: nil,
            default: nil,
            autogenerate_id: nil,
            index: %{},
            source_field: %{},
            schema_erl_prefix: nil,
            record_name: nil,
            attributes: [],
            extra_key: nil

  @type t :: %__MODULE__{}

  def new({table, schema, _prefix}) do
    new(%{source: table, schema: schema})
  end

  def new(%{source: table, schema: schema} = meta) do
    table = String.to_atom(table)
    schema = schema
    record_name = record_name(schema)
    keys = schema.__schema__(:primary_key)
    loaded = schema.__schema__(:loaded)

    %__MODULE__{
      table: table,
      schema: schema,
      record_name: record_name,
      loaded: loaded,
      autogenerate_id: meta[:autogenerate_id],
      schema_erl_prefix: schema |> to_string() |> String.replace(".", "_")
    }
    |> build_extra_key(keys)
    |> build_attributes()
    |> build_index()
    |> build_default()
    |> build_source_field()
  end

  def new(%{schema: schema} = meta) do
    new(Map.put(meta, :source, schema.__schema__(:source)))
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

  defp build_extra_key(source, []), do: source

  defp build_extra_key(source, [_]), do: source

  defp build_extra_key(source, keys) do
    extra_key =
      keys
      |> Enum.with_index()
      |> Enum.reduce(%{}, fn {key, i}, acc ->
        Map.put(acc, key, i)
      end)

    %{source | extra_key: extra_key}
  end

  defp build_attributes(%{schema: schema, extra_key: nil} = source),
    do: %{source | attributes: schema_sources(schema)}

  defp build_attributes(%{schema: schema} = source),
    do: %{source | attributes: [:__key__ | schema_sources(schema)]}

  defp build_index(%{attributes: attributes} = source) do
    index =
      attributes
      |> Enum.with_index()
      |> Enum.reduce(%{}, fn
        {:__key__, _}, acc -> acc
        {a, i}, acc -> Map.put(acc, a, i + 1)
      end)

    %{source | index: index}
  end

  defp build_source_field(%{schema: schema} = source) do
    map =
      schema
      |> apply(:__schema__, [:fields])
      |> Enum.reduce(%{}, &Map.put(&2, schema.__schema__(:field_source, &1), &1))

    %{source | source_field: map}
  end

  defp build_default(%{attributes: attributes, record_name: record_name} = source) do
    default =
      nil
      |> Tuple.duplicate(length(attributes))
      |> Tuple.insert_at(0, record_name)
      |> maybe_default_extra_key(source)

    %{source | default: default}
  end

  defp maybe_default_extra_key(record, %{extra_key: nil}), do: record

  defp maybe_default_extra_key(record, %{extra_key: extra_key}) do
    put_elem(record, 1, Tuple.duplicate(nil, Enum.count(extra_key)))
  end

  defp schema_sources(schema) do
    schema
    |> apply(:__schema__, [:fields])
    |> Enum.map(&schema.__schema__(:field_source, &1))
  end
end
