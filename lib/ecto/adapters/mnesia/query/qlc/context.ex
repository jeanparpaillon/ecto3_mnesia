defmodule Ecto.Adapters.Mnesia.Query.Qlc.Context do
  @moduledoc false

  alias Ecto.Adapters.Mnesia.Source

  defstruct sources: [],
            sources_index: %{},
            params: [],
            qualifiers: [],
            joins: [],
            bindings: [],
            index: 0

  @type t :: %__MODULE__{}

  def new(sources) do
    sources_index =
      sources
      |> Enum.with_index()
      |> Map.new(fn {s, i} -> {i, s} end)

    %__MODULE__{sources: sources, sources_index: sources_index}
  end

  def add_binding(context, {field, source}, value) do
    erl_var = Source.to_erl_var(source, field)
    bind_var = :"B#{context.index}_#{erl_var}"
    bindings = [{bind_var, value} | context.bindings]
    {erl_var, bind_var, %{context | index: context.index + 1, bindings: bindings}}
  end

  def add_binding(context, binding, value) when is_binary(binding) do
    bind_var = :"B#{String.replace(binding, ~r/\s/, "")}"
    bindings = [{bind_var, value} | context.bindings]
    {value, bind_var, %{context | index: context.index + 1, bindings: bindings}}
  end
end
