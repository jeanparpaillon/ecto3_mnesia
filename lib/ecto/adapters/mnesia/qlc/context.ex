defmodule Ecto.Adapters.Mnesia.Qlc.Context do
  @moduledoc false

  defmodule Source do
    defstruct table: nil, schema: nil, loaded: nil, info: nil

    @type t :: %__MODULE__{}

    def new({table, schema}) do
      %__MODULE__{
        table: table,
        info: :mnesia.table_info(table, :all),
        schema: schema,
        loaded: apply(schema, :__schema__, [:loaded])
      }
    end
  end

  alias Ecto.Adapters.Mnesia.Record

  defstruct sources: [], params: [], qualifiers: [], joins: [], bindings: [], index: 0

  @type t :: %__MODULE__{}

  def new(sources) do
    %__MODULE__{sources: Enum.map(sources, &Source.new/1)}
  end

  def add_binding(context, {field, source}, value) do
    erl_var = Record.Attributes.to_erl_var(field, source)
    bind_var = :"B#{context.index}_#{erl_var}"
    bindings = [{bind_var, value} | context.bindings]
    {erl_var, bind_var, %{context | index: context.index + 1, bindings: bindings}}
  end
end
