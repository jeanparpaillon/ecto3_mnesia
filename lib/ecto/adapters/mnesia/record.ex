defmodule Ecto.Adapters.Mnesia.Record do
  @moduledoc false
  alias Ecto.Adapter.Schema
  alias Ecto.Adapters.Mnesia
  alias Ecto.Adapters.Mnesia.Source

  @type t :: tuple()
  @type context :: Source.t()

  # new api
  @spec new(tuple() | Keyword.t() | map() | Ecto.Schema.t(), Source.t()) :: t()
  def new(data, source) when is_tuple(data) do
    pattern = source.info.wild_pattern
    Tuple.insert_at(data, 0, elem(pattern, 0))
  end

  def new(%{__struct__: _} = struct, source) do
    struct |> Map.from_struct() |> Map.drop([:__meta__]) |> new(source)
  end

  def new(data, source) when is_list(data) do
    data |> Map.new() |> new(source)
  end

  def new(data, source) when is_map(data) do
    pattern = source.info.wild_pattern

    source.index
    |> Enum.reduce(pattern, fn {field, i}, acc ->
      put_elem(acc, i, Map.get(data, field))
    end)
  end

  # new api
  @spec update(t(), Keyword.t(), Source.t(), [atom()] | :all) :: t()
  def update(record, params, source, replace \\ :all) do
    params
    |> Enum.reduce(record, fn {field, value}, acc ->
      if replace == :all or Enum.member?(replace, field) do
        put_elem(acc, source.index[field], value)
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
  def to_schema(record, %{loaded: loaded, index: index}) do
    index
    |> Enum.reduce(loaded, fn {field, i}, acc ->
      Map.put(acc, field, elem(record, i))
    end)
  end

  @spec uniques(Keyword.t(), context()) :: [{atom(), term()}]
  def uniques(params, context) do
    keys = apply(context.schema, :__schema__, [:primary_key])

    keys
    |> Enum.reduce([], fn key, acc ->
      case Keyword.fetch(params, key) do
        {:ok, value} -> [{key, value} | acc]
        :error -> acc
      end
    end)
  end

  @spec gen_id(Keyword.t(), context()) :: Keyword.t()
  def gen_id(params, source) do
    case source.autogenerate_id do
      nil ->
        params

      {_key, id_source, type} ->
        if params[id_source] do
          params
        else
          record_name = record_name(source)
          Keyword.put(params, id_source, Mnesia.autogenerate({{record_name, id_source}, type}))
        end
    end
  end

  @spec record_name(Source.t()) :: atom()
  def record_name(%{schema: schema}) do
    if function_exported?(schema, :__record_name__, 0) do
      apply(schema, :__record_name__, [])
    else
      schema
    end
  end

  ###
  ### Priv
  ###
  defmodule Attributes do
    @moduledoc false

    alias Ecto.Adapters.Mnesia.Source

    @type t :: list()

    @spec to_erl_var(attribute :: atom(), Source.t()) :: erl_var :: String.t()
    def to_erl_var(attribute, %{schema_erl_prefix: prefix}) do
      prefix <> "_" <> (attribute |> to_string() |> String.capitalize())
    end
  end
end
