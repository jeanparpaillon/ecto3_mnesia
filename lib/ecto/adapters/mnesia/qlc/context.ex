defmodule Ecto.Adapters.Mnesia.Qlc.Context do
  @moduledoc false

  alias Ecto.Adapters.Mnesia.Source

  defstruct sources: [], params: [], qualifiers: [], joins: [], bindings: [], index: 0

  @type t :: %__MODULE__{}

  def new(sources) do
    %__MODULE__{sources: sources}
  end

  def add_binding(context, {field, source}, value) do
    erl_var = Source.to_erl_var(source, field)
    bind_var = :"B#{context.index}_#{erl_var}"
    bindings = [{bind_var, value} | context.bindings]
    {erl_var, bind_var, %{context | index: context.index + 1, bindings: bindings}}
  end
end
