defmodule Ecto.Adapters.Mnesia.Record do
  @moduledoc false
  import Ecto.Adapters.Mnesia.Table,
    only: [
      attributes: 1,
      field_index: 2,
      field_name: 2
    ]

  alias Ecto.Adapters.Mnesia
  alias Ecto.Adapters.Mnesia.Recordable

  @type t :: tuple()
  @type context :: %{
          :table_name => atom(),
          :schema_meta => %{
            optional(:autogenerate_id) =>
              {schema_field :: atom(), source_field :: atom(), Ecto.Type.t()},
            optional(:context) => term(),
            optional(:prefix) => binary() | nil,
            :schema => atom(),
            optional(:source) => binary()
          },
          optional(:adapter_meta) => Ecto.Adapter.Schema.adapter_meta()
        }

  @spec to_schema(record :: t(), context()) :: struct()
  def to_schema(record, context) do
    Enum.reduce(
      attributes(context.table_name),
      # schema struct
      struct(context.schema_meta.schema),
      fn attribute, struct ->
        %{struct | attribute => elem(record, field_index(attribute, context.table_name))}
      end
    )
  end

  @spec id(Keyword.t(), context()) :: term() | nil
  def id(params, context) do
    case apply(get_in(context, [:schema_meta, :schema]), :__schema__, [:primary_key]) do
      [key] -> params[key]
      _ -> nil
    end
  end

  @spec gen_id(Keyword.t(), context()) :: Keyword.t()
  def gen_id(params, context) do
    case get_in(context, [:schema_meta, :autogenerate_id]) do
      nil ->
        params

      {_key, source, type} ->
        if params[source] do
          params
        else
          record_name = context |> new_struct() |> Recordable.record_name()
          Keyword.put(params, source, Mnesia.autogenerate({{record_name, source}, type}))
        end
    end
  end

  @spec build(params :: Keyword.t() | [tuple()], context()) :: record :: t()
  def build(params, context) do
    table_name = context.table_name
    record_name = context |> new_struct() |> Recordable.record_name()

    attributes(table_name)
    |> Enum.map(fn attribute ->
      case Keyword.fetch(params, attribute) do
        {:ok, value} -> value
        :error -> nil
      end
    end)
    |> List.insert_at(0, record_name)
    |> List.to_tuple()
  end

  @spec put_change(record :: t(), params :: Keyword.t(), context()) :: record :: t()
  def put_change(record, params, context) do
    table_name = context.table_name
    record_name = context |> new_struct() |> Recordable.record_name()

    record
    |> Tuple.to_list()
    |> List.delete_at(0)
    |> Enum.with_index()
    |> Enum.map(fn {attribute, index} ->
      case Keyword.fetch(params, field_name(index, table_name)) do
        {:ok, value} -> value
        :error -> attribute
      end
    end)
    |> List.insert_at(0, record_name)
    |> List.to_tuple()
  end

  @spec merge(Keyword.t(), record :: t(), context(), [atom()]) :: Keyword.t()
  def merge(new_params, record, context, replace) do
    old_params = record |> Tuple.to_list() |> List.delete_at(0)

    [attributes(context.table_name), old_params]
    |> List.zip()
    |> Enum.reduce([], fn {field, old}, acc ->
      if Enum.member?(replace, field) do
        case Keyword.fetch(new_params, field) do
          {:ok, new} -> Keyword.put(acc, field, new)
          :error -> Keyword.put(acc, field, old)
        end
      else
        Keyword.put(acc, field, old)
      end
    end)
  end

  @spec attribute(record :: t(), field :: atom(), context()) :: attribute :: any()
  def attribute(record, field, context) do
    table_name = context.table_name

    elem(record, field_index(field, table_name))
  end

  defp new_struct(context) do
    apply(get_in(context, [:schema_meta, :schema]), :__schema__, [:loaded])
  end

  defmodule Attributes do
    @moduledoc false

    @type t :: list()

    @spec to_erl_var(attribute :: atom(), source :: tuple()) :: erl_var :: String.t()
    def to_erl_var(attribute, {_table_name, schema}) do
      (schema |> to_string() |> String.split(".") |> List.last()) <>
        (attribute |> Atom.to_string() |> String.capitalize())
    end
  end
end
