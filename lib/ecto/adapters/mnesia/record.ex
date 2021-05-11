defmodule Ecto.Adapters.Mnesia.Record do
  @moduledoc false
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
    loaded = loaded(context)

    loaded
    |> Map.merge(Enum.into(Recordable.load(loaded, record, context), %{}))
  end

  @spec to_record(params :: Keyword.t() | [tuple()], context()) :: record :: t()
  def to_record(params, context) do
    struct = loaded(context)
    record_name = Recordable.record_name(struct)

    struct
    |> Recordable.dump(params, context)
    |> List.insert_at(0, record_name)
    |> List.to_tuple()
  end

  @spec to_keyword(t(), context()) :: Keyword.t()
  def to_keyword(record, context) do
    context |> loaded() |> Recordable.load(record, context)
  end

  @spec uniques(Keyword.t(), context()) :: [{atom(), term()}]
  def uniques(params, context) do
    keys = apply(context.schema_meta.schema, :__schema__, [:primary_key])

    keys
    |> Enum.reduce([], fn key, acc ->
      case Keyword.fetch(params, key) do
        {:ok, value} -> [{key, value} | acc]
        :error -> acc
      end
    end)
  end

  @spec update(orig :: Keyword.t(), new :: Keyword.t(), replace :: list() | :all, context()) ::
          Keyword.t()
  def update(orig, new, replace \\ :all, _context) do
    orig
    |> Enum.reduce([], fn {field, old}, acc ->
      if replace == :all or Enum.member?(replace, field) do
        case Keyword.fetch(new, field) do
          {:ok, value} -> Keyword.put(acc, field, value)
          :error -> Keyword.put(acc, field, old)
        end
      else
        Keyword.put(acc, field, old)
      end
    end)
  end

  @spec select(record :: t(), attributes :: [atom()], context()) :: [term()]
  def select(record, fields, context) do
    loaded = loaded(context)
    fields = MapSet.new(fields)

    loaded
    |> Recordable.load(record, context)
    |> Enum.filter(&Enum.member?(fields, elem(&1, 0)))
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
          record_name = context |> loaded() |> Recordable.record_name()
          Keyword.put(params, source, Mnesia.autogenerate({{record_name, source}, type}))
        end
    end
  end

  ###
  ### Priv
  ###
  defp loaded(context) do
    apply(get_in(context, [:schema_meta, :schema]), :__schema__, [:loaded])
  end

  defmodule Attributes do
    @moduledoc false

    alias Ecto.Adapters.Mnesia.Qlc.Context

    @type t :: list()

    @spec to_erl_var(attribute :: atom(), Context.Source.t()) :: erl_var :: String.t()
    def to_erl_var(attribute, source) do
      (source.schema |> to_string() |> String.split(".") |> List.last()) <>
        (attribute |> Atom.to_string() |> String.capitalize())
    end
  end
end
