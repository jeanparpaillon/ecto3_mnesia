defmodule Ecto.Adapters.Mnesia.Query.Qlc do
  @moduledoc """
  Builds qlc query out of Ecto.Query
  """
  alias Ecto.Adapters.Mnesia.Query
  alias Ecto.Adapters.Mnesia.Query.Qlc.Context
  alias Ecto.Adapters.Mnesia.Source
  alias Ecto.Query.BooleanExpr
  alias Ecto.Query.QueryExpr
  alias Ecto.Query.SelectExpr

  @behaviour Query
  @dialyzer {:no_return, [build_query: 4, to_query_handle: 2]}
  @dialyzer :no_opaque

  @order_mapping %{
    asc: :ascending,
    desc: :descending
  }

  def query(select, joins, sources) do
    context = Context.new(sources)

    q = fn
      [%BooleanExpr{}] = wheres -> build_query(select, joins, wheres, context)
      filters -> build_query(select, joins, filters, context)
    end

    {:cache, q}
  end

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
    {vars, generators} = select(select, context)

    fn params ->
      context =
        %{context | params: params}
        |> qualifiers(filters)
        |> joins(joins)

      bindings =
        Enum.reduce(context.bindings, :erl_eval.new_bindings(), fn {k, v}, acc ->
          :erl_eval.add_binding(k, v, acc)
        end)

      to_query_handle({:lc, 1, vars, generators ++ context.joins ++ context.qualifiers}, bindings)
    end
  end

  defp to_query_handle(expr, bindings) do
    {:ok, {:call, _, _, handle}} = :qlc_pt.transform_expression(expr, bindings)
    {:value, qlc_lc, _} = :erl_eval.exprs(handle, bindings)
    :qlc.q(qlc_lc, [])
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
    {q_fields(select, context),
     Enum.map(context.sources, fn source ->
       record_pattern = {:tuple, 1, [{:var, 1, :_} | Source.qlc_attributes_pattern(source)]}

       {:generate, 1, record_pattern,
        {:call, 1, {:remote, 1, {:atom, 1, :mnesia}, {:atom, 1, :table}},
         [{:atom, 1, source.table}]}}
     end)}
  end

  defp q_fields(%SelectExpr{fields: fields}, context) do
    {:tuple, 1, Enum.map(fields, &q_field(&1, context))}
  end

  defp q_fields(:all, %{sources: [source | _t]}) do
    {:tuple, 1, Source.qlc_attributes_pattern(source)}
  end

  defp q_fields(_, %{sources: [source | _t]}) do
    {:tuple, 1, Source.qlc_attributes_pattern(source)}
  end

  defp q_field({{_, _, [{:&, [], [source_index]}, field]}, [], []}, context) do
    {:var, 1, Source.to_erl_var(context.sources_index[source_index], field)}
  end

  defp q_field(_, _), do: nil

  defp fields(%SelectExpr{fields: fields}, context) do
    Enum.map(fields, &field(&1, context))
  end

  defp fields(:all, %{sources: [source | _t]}) do
    Source.qlc_attributes_pattern(source)
  end

  defp fields(_, %{sources: [source | _t]}) do
    Source.qlc_attributes_pattern(source)
  end

  defp field({{_, _, [{:&, [], [source_index]}, field]}, [], []}, context) do
    Source.to_erl_var(context.sources_index[source_index], field)
  end

  defp field(_, _), do: nil

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

  # Returns erlang forms from Ecto Query AST
  defp to_qlc(true, context), do: {{:atom, 1, true}, context}

  defp to_qlc({field, value}, %{sources: [source]} = context) do
    {erl_var, bind_var, context} = Context.add_binding(context, {field, source}, value)
    {{:op, 1, :==, {:var, 1, erl_var}, {:var, 1, bind_var}}, context}
  end

  defp to_qlc(
         {:and, [], [a, b]},
         context
       ) do
    {a_qlc, context} = to_qlc(a, context)
    {b_qlc, context} = to_qlc(b, context)
    {{:op, 1, :andalso, a_qlc, b_qlc}, context}
  end

  defp to_qlc(
         {:or, [], [a, b]},
         context
       ) do
    {a_qlc, context} = to_qlc(a, context)
    {b_qlc, context} = to_qlc(b, context)
    {{:op, 1, :orelse, a_qlc, b_qlc}, context}
  end

  defp to_qlc(
         {:is_nil, [], [{{:., [], [{:&, [], [source_index]}, field]}, [], []}]},
         context
       ) do
    source = Enum.at(context.sources, source_index)
    erl_var = Source.to_erl_var(source, field)
    {{:op, 1, :==, {:var, 1, erl_var}, {:atom, 1, nil}}, context}
  end

  defp to_qlc({:not, [], [expr]}, context) do
    {expr_qlc, context} = to_qlc(expr, context)
    {{:op, 1, :not, expr_qlc}, context}
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

    {{:call, 1, {:remote, 1, {:atom, 1, :lists}, {:atom, 1, :member}},
      [{:var, 1, erl_var}, {:var, 1, bind_var}]}, context}
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
    erl_var = Source.to_erl_var(key_source, key_field)
    value = Source.to_erl_var(value_source, value_field)
    {{:op, 1, to_qlc_op(op), {:var, 1, erl_var}, {:var, 1, value}}, context}
  end

  defp to_qlc(
         {op, [], [{{:., [], [{:&, [], [source_index]}, field]}, [], []}, value]},
         context
       ) do
    source = Enum.at(context.sources, source_index)
    {erl_var, bind_var, context} = Context.add_binding(context, {field, source}, value)
    {{:op, 1, to_qlc_op(op), {:var, 1, erl_var}, {:var, 1, bind_var}}, context}
  end

  defp to_qlc_op(:!=), do: :"=/="
  defp to_qlc_op(:<=), do: :"=<"
  defp to_qlc_op(op), do: op
end
