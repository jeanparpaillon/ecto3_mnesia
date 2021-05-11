defmodule Ecto.Adapters.Mnesia.Record do
  @moduledoc false
  alias Ecto.Adapters.Mnesia
  alias Ecto.Adapters.Mnesia.Recordable
  alias Ecto.Adapters.Mnesia.Source

  @type t :: tuple()
  @type context :: Source.t()

  @spec to_schema(record :: t(), context()) :: struct()
  def to_schema(record, %{loaded: loaded} = context) do
    loaded
    |> Map.merge(Enum.into(Recordable.load(loaded, record, context), %{}))
  end

  @spec to_record(params :: Keyword.t() | [tuple()], context()) :: record :: t()
  def to_record(params, %{loaded: loaded} = context) do
    record_name = Recordable.record_name(loaded)

    loaded
    |> Recordable.dump(params, context)
    |> List.insert_at(0, record_name)
    |> List.to_tuple()
  end

  @spec to_keyword(t(), context()) :: Keyword.t()
  def to_keyword(record, context) do
    context.loaded() |> Recordable.load(record, context)
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
  def select(record, fields, %{loaded: loaded} = context) do
    fields = MapSet.new(fields)

    loaded
    |> Recordable.load(record, context)
    |> Enum.filter(&Enum.member?(fields, elem(&1, 0)))
  end

  @spec gen_id(Keyword.t(), context()) :: Keyword.t()
  def gen_id(params, %{loaded: loaded} = context) do
    case context.autogenerate_id do
      nil ->
        params

      {_key, source, type} ->
        if params[source] do
          params
        else
          record_name = loaded |> Recordable.record_name()
          Keyword.put(params, source, Mnesia.autogenerate({{record_name, source}, type}))
        end
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
    def to_erl_var(attribute, source) do
      (source.schema |> to_string() |> String.split(".") |> List.last()) <>
        (attribute |> Atom.to_string() |> String.capitalize())
    end
  end
end
