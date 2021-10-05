defmodule Ecto.Adapters.Mnesia.Query.Qlc.Context do
  @moduledoc false

  alias Ecto.Adapters.Mnesia.Source

  defstruct sources: [],
            sources_index: %{},
            qualifiers: [],
            joins: [],
            bindings: [],
            extra_bindings: [],
            extra_index: 0

  @type t :: %__MODULE__{}

  def new(sources) do
    sources_index =
      sources
      |> Enum.with_index()
      |> Map.new(fn {s, i} -> {i, s} end)

    %__MODULE__{
      sources: sources,
      sources_index: sources_index
    }
  end

  def source_var(%{sources_index: sources}, index, field) do
    sources
    |> Map.get(index)
    |> Source.to_erl_var(field)
  end

  def binding_var(context, i) do
    v = :"B#{i}"
    {v, %{context | bindings: [v | context.bindings]}}
  end

  def bindings(context), do: Enum.reverse(context.bindings)

  def extra_binding(context, value) do
    var = :"EB#{context.extra_index}"

    {var,
     %{
       context
       | extra_index: context.extra_index + 1,
         extra_bindings: [{var, value} | context.extra_bindings]
     }}
  end

  def extra_bindings(context), do: Enum.reverse(context.extra_bindings)
end
