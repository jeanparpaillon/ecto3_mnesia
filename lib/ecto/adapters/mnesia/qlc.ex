defmodule Ecto.Adapters.Mnesia.Qlc do
  @moduledoc false
  require Qlc

  alias Ecto.Adapters.Mnesia.Qlc.Context
  alias Ecto.Adapters.Mnesia.Record
  alias Ecto.Adapters.Mnesia.Table
  alias Ecto.Query.BooleanExpr
  alias Ecto.Query.QueryExpr
  alias Ecto.Query.SelectExpr

  @order_mapping %{
    asc: :ascending,
    desc: :descending
  }

  @spec query(%SelectExpr{} | :all, any(), list(tuple())) ::
          (list() -> (params :: list() -> query_handle :: :qlc.query_handle()))
  def query(select, joins, sources) do
    context = Context.new(sources)

    fn
      [%BooleanExpr{}] = wheres -> build_query(select, joins, wheres, context)
      filters -> build_query(select, joins, filters, context)
    end
  end

  @spec sort(list(%QueryExpr{}), %SelectExpr{}, list(tuple())) ::
          (query_handle :: :qlc.query_handle() -> query_handle :: :qlc.query_handle())
  def sort([], _select, _sources) do
    fn query -> query end
  end

  def sort(order_bys, select, sources) do
    context = Context.new(sources)

    fn query ->
      Enum.reduce(order_bys, query, fn
        %QueryExpr{expr: expr}, query1 ->
          Enum.reduce(expr, query1, fn {order, field_expr}, query2 ->
            field = field(field_expr, context)
            field_index = Enum.find_index(fields(select, context), fn e -> e == field end)

            Qlc.keysort(query2, field_index, order: @order_mapping[order])
          end)
      end)
    end
  end

  @spec answers(limit :: %QueryExpr{} | nil, offset :: %QueryExpr{} | nil) ::
          (query_handle :: :qlc.query_handle(), context :: Keyword.t() -> list(tuple()))
  def answers(limit, offset) do
    fn query, context ->
      limit = unbind_limit(limit, context)
      offset = unbind_offset(offset, context)
      cursor = Qlc.cursor(query)

      if offset > 0 do
        :qlc.next_answers(cursor.c, offset)
      end

      :qlc.next_answers(cursor.c, limit)
      |> :qlc.e()
    end
  end

  defp build_query(select, joins, filters, context) do
    select = select(select, context)

    fn params ->
      context =
        %{context | params: params}
        |> qualifiers(filters)
        |> joins(joins)

      comprehension =
        [select, Enum.join(context.joins, ", "), Enum.join(context.qualifiers, ", ")]
        |> Enum.reject(fn component -> String.length(component) == 0 end)
        |> Enum.join(", ")

      Qlc.q("[#{comprehension}]", context.bindings)
    end
  end

  defp unbind_limit(nil, _context), do: :all_remaining

  defp unbind_limit(%QueryExpr{expr: {:^, [], [param_index]}}, context) do
    Enum.at(context[:params], param_index)
  end

  defp unbind_limit(%QueryExpr{expr: limit}, _context) when is_integer(limit), do: limit

  defp unbind_offset(nil, _context), do: 0

  defp unbind_offset(%QueryExpr{expr: {:^, [], [param_index]}}, context) do
    Enum.at(context[:params], param_index)
  end

  defp unbind_offset(%QueryExpr{expr: offset}, _context) when is_integer(offset), do: offset

  defp select(select, context) do
    fields = fields(select, context)

    "{#{Enum.join(fields, ", ")}} || " <>
      (Enum.map(context.sources, fn source ->
         "#{record_pattern(source)} <- mnesia:table('#{source.table}')"
       end)
       |> Enum.join(", "))
  end

  defp fields(%SelectExpr{fields: fields}, context) do
    Enum.flat_map(context.sources, fn _source ->
      Enum.map(fields, &field(&1, context))
      |> Enum.reject(&is_nil(&1))
    end)
  end

  defp fields(:all, %{sources: [source | _t]}) do
    source.schema.__schema__(:fields)
    |> Enum.map(&Record.Attributes.to_erl_var(&1, source))
  end

  defp fields(_, %{sources: [source | _t]}) do
    source.schema.__schema__(:fields)
    |> Enum.map(&Record.Attributes.to_erl_var(&1, source))
  end

  defp field({{_, _, [{:&, [], [source_index]}, field]}, [], []}, %{sources: sources}) do
    case Enum.at(sources, source_index) do
      source -> Record.Attributes.to_erl_var(field, source)
    end
  end

  defp qualifiers(context, wheres) do
    context =
      wheres
      |> Enum.map(fn
        %BooleanExpr{expr: expr} -> expr
        {field, value} -> {field, value}
      end)
      |> Enum.reduce(context, fn where, acc ->
        {qlc, acc} = to_qlc(where, acc)
        %{acc | qualifiers: [qlc | acc.qualifiers]}
      end)

    %{context | qualifiers: Enum.reverse(context.qualifiers)}
  end

  defp joins(context, joins) do
    context =
      joins
      |> Enum.map(fn %{on: %{expr: expr}} -> expr end)
      |> Enum.reduce(context, fn join, acc ->
        {qlc, acc} = to_qlc(join, acc)
        %{acc | joins: [qlc | acc.joins]}
      end)

    %{context | joins: Enum.reverse(context.joins)}
  end

  defp record_pattern(source) do
    "{#{Enum.join(record_pattern_attributes(source), ", ")}}"
  end

  defp record_pattern_attributes(source) do
    Table.attributes(source.table)
    |> Enum.map(fn attribute -> Record.Attributes.to_erl_var(attribute, source) end)
    |> List.insert_at(0, "Schema")
  end

  defp to_qlc(true, context), do: {"true", context}

  defp to_qlc({field, value}, %{sources: [source]} = context) do
    {erl_var, bind_var, context} = Context.add_binding(context, {field, source}, value)
    {"#{erl_var} == #{bind_var}", context}
  end

  defp to_qlc(
         {:and, [], [a, b]},
         context
       ) do
    {a_qlc, context} = to_qlc(a, context)
    {b_qlc, context} = to_qlc(b, context)
    {"(#{a_qlc} andalso #{b_qlc})", context}
  end

  defp to_qlc(
         {:or, [], [a, b]},
         context
       ) do
    {a_qlc, context} = to_qlc(a, context)
    {b_qlc, context} = to_qlc(b, context)
    {"(#{a_qlc} orelse #{b_qlc})", context}
  end

  defp to_qlc(
         {:is_nil, [], [{{:., [], [{:&, [], [source_index]}, field]}, [], []}]},
         context
       ) do
    source = Enum.at(context.sources, source_index)
    erl_var = Record.Attributes.to_erl_var(field, source)
    {"#{erl_var} == nil", context}
  end

  defp to_qlc({:not, [], [expr]}, context) do
    {expr_qlc, context} = to_qlc(expr, context)
    {"not (#{expr_qlc})", context}
  end

  defp to_qlc(
         {:in, [],
          [{{:., [], [{:&, [], [source_index]}, field]}, [], []}, {:^, [], [index, length]}]},
         context
       ) do
    values = Enum.slice(context.params, index, length)
    to_qlc({:in, [], [{{:., [], [{:&, [], [source_index]}, field]}, [], []}, values]}, context)
  end

  defp to_qlc(
         {:in, [], [{{:., [], [{:&, [], [source_index]}, field]}, [], []}, values]},
         context
       )
       when is_list(values) do
    source = Enum.at(context.sources, source_index)
    {erl_var, bind_var, context} = Context.add_binding(context, {field, source}, values)
    {"lists:member(#{erl_var}, #{bind_var})", context}
  end

  defp to_qlc(
         {op, [], [{{:., [], [{:&, [], [source_index]}, field]}, [], []}, {:^, [], [index]}]},
         context
       ) do
    value = Enum.at(context.params, index)
    to_qlc({op, [], [{{:., [], [{:&, [], [source_index]}, field]}, [], []}, value]}, context)
  end

  defp to_qlc(
         {op, [],
          [
            {{:., [], [{:&, [], [key_source_index]}, key_field]}, [], []},
            {{:., [], [{:&, [], [value_source_index]}, value_field]}, [], []}
          ]},
         context
       ) do
    key_source = Enum.at(context.sources, key_source_index)
    value_source = Enum.at(context.sources, value_source_index)
    erl_var = Record.Attributes.to_erl_var(key_field, key_source)
    value = Record.Attributes.to_erl_var(value_field, value_source)
    {"#{erl_var} #{op} #{value}", context}
  end

  defp to_qlc(
         {:!=, [], [{{:., [], [{:&, [], [source_index]}, field]}, [], []}, value]},
         context
       ) do
    source = Enum.at(context.sources, source_index)
    {erl_var, bind_var, context} = Context.add_binding(context, {field, source}, value)
    {"#{erl_var} =/= #{bind_var}", context}
  end

  defp to_qlc(
         {op, [], [{{:., [], [{:&, [], [source_index]}, field]}, [], []}, value]},
         context
       ) do
    source = Enum.at(context.sources, source_index)
    {erl_var, bind_var, context} = Context.add_binding(context, {field, source}, value)
    {"#{erl_var} #{op} #{bind_var}", context}
  end
end
