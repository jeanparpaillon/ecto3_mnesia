defmodule Ecto.Adapters.Mnesia.Record do
  @moduledoc false
  alias Ecto.Adapter.Schema
  alias Ecto.Adapters.Mnesia
  alias Ecto.Adapters.Mnesia.Source

  @type t :: tuple()

  # new api
  @spec new(tuple() | Keyword.t() | map() | Ecto.Schema.t(), Source.t()) :: t()
  def new(data, source) when is_tuple(data) do
    Tuple.insert_at(data, 0, source.record_name)
  end

  def new(%{__struct__: _} = struct, source) do
    struct
    |> Map.from_struct()
    |> Map.drop([:__meta__])
    |> Enum.map(fn {field, value} -> {source.schema.__schema__(:field_source, field), value} end)
    |> new(source)
  end

  def new(data, source) when is_list(data) or is_map(data) do
    pattern = source.default
    update(pattern, data, source)
  end

  # new api
  @spec update(t(), Enumerable.t(), Source.t(), [atom()] | :all) :: t()
  def update(record, params, source, replace \\ :all) do
    params
    |> Enum.reduce(record, fn {field, value}, acc ->
      if replace == :all or Enum.member?(replace, field) do
        case source.index[field] do
          nil ->
            # Association or vitual field
            acc

          field_index ->
            acc
            |> put_elem(field_index, value)
            |> maybe_update_key(field, field_index, source)
        end
      else
        acc
      end
    end)
  end

  # new api
  @spec select(t(), [atom()], Source.t()) :: Schema.fields()
  def select(record, fields, %{index: index}) do
    Enum.map(fields, &{&1, elem(record, index[&1])})
  end

  @spec to_schema(t(), Source.t()) :: Ecto.Schema.t()
  def to_schema(record, %{loaded: loaded, index: index, source_field: fields}) do
    index
    |> Enum.reduce(loaded, fn {field, i}, acc ->
      Map.put(acc, fields[field], elem(record, i))
    end)
  end

  @spec gen_id(Keyword.t(), Source.t()) :: Keyword.t()
  def gen_id(params, source) do
    case source.autogenerate_id do
      nil ->
        params

      {_key, id_source, type} ->
        if params[id_source] do
          params
        else
          Keyword.put(
            params,
            id_source,
            Mnesia.autogenerate({{source.record_name, id_source}, type})
          )
        end
    end
  end

  ###
  ### Priv
  ###
  defp maybe_update_key(record, _field, _field_index, %{extra_key: nil}),
    do: record

  defp maybe_update_key(record, field, field_index, %{extra_key: extra_key}) do
    case Map.fetch(extra_key, field) do
      {:ok, key_index} ->
        key =
          record
          |> elem(1)
          |> put_elem(key_index, elem(record, field_index))

        put_elem(record, 1, key)

      :error ->
        record
    end
  end
end
