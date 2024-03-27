defmodule Ecto.Adapters.Mnesia.Query.Qlc do
  alias Ecto.Query.QueryExpr

  @moduledoc """
  Builds qlc query out of Ecto.Query
  """
  require Ecto.Adapters.Mnesia.Query

  alias Ecto.Adapters.Mnesia.Query
  alias Ecto.Adapters.Mnesia.Query.Qlc.Context
  alias Ecto.Adapters.Mnesia.Source
  alias Ecto.Query.BooleanExpr
  alias Ecto.Query.QueryExpr
  alias Ecto.Query.SelectExpr

  @behaviour Query
  # @dialyzer {:nowarn_function, qlc_handle: 2}

  @order_mapping %{
    asc: :ascending,
    desc: :descending
  }

  @type query_expr :: %QueryExpr{}

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
            :qlc.keysort(field_index + 1, query2, order: @order_mapping[order])
          end)
      end)
    end
  end

  @spec answers(limit :: query_expr() | nil, offset :: query_expr() | nil) ::
          (query_handle :: :qlc.query_handle(), context :: Keyword.t() -> list(tuple()))
  def answers(limit, offset) do
    fn query, params ->
      Stream.resource(
        fn ->
          limit = unbind_limit(limit, params)
          offset = unbind_offset(offset, params)
          cursor = :qlc.cursor(query)

          if offset > 0 do
            _ = :qlc.next_answers(cursor, offset)
          end

          {cursor, limit}
        end,
        fn
          {cursor, 0} ->
            {:halt, cursor}

          {cursor, limit} ->
            case :qlc.next_answers(cursor, limit) do
              [] -> {:halt, cursor}
              results -> {results, {cursor, max(0, limit - length(results))}}
            end
        end,
        fn cursor -> :qlc.delete_cursor(cursor) end
      )
    end
  end

  defp build_query(select, joins, filters, context) do
    {vars, generators} = select(select, context)

    context =
      context
      |> qualifiers(filters)
      |> joins(joins)

    binding_vars = Context.bindings(context)
    extra_bindings = Context.extra_bindings(context)

    pt_bindings =
      binding_vars
      |> Enum.map(&{&1, nil})
      |> Kernel.++(extra_bindings)

    expr = {:lc, anno(), vars, generators ++ context.joins ++ context.qualifiers}
    handle = qlc_handle(expr, pt_bindings)

    fn params ->
      bindings =
        binding_vars
        |> Enum.zip(params)
        |> Kernel.++(extra_bindings)

      {:value, qlc_lc, _} = :erl_eval.exprs(handle, bindings)
      :qlc.q(qlc_lc, [])
    end
  end

  @spec qlc_handle(any(), any()) :: any() | none()
  defp qlc_handle(expr, bindings) do
    {:ok, {:call, _, _, handle}} = :qlc_pt.transform_expression(expr, bindings)
    handle
  end

  defp anno, do: :erl_anno.new(1)

  defp unbind_limit(nil, _params), do: 10

  defp unbind_limit(%QueryExpr{expr: {:^, [], [param_index]}}, params) do
    Enum.at(params, param_index)
  end

  defp unbind_limit(%QueryExpr{expr: limit}, _params) when is_integer(limit), do: limit

  defp unbind_offset(nil, _context), do: 0

  defp unbind_offset(%QueryExpr{expr: {:^, [], [param_index]}}, params) do
    Enum.at(params, param_index)
  end

  defp unbind_offset(%QueryExpr{expr: offset}, _params) when is_integer(offset), do: offset

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
    erl_var = Source.to_erl_var(source, field)
    {var, context} = Context.extra_binding(context, value)
    {{:op, 1, :==, {:var, 1, erl_var}, {:var, 1, var}}, context}
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
    erl_var = Context.source_var(context, source_index, field)
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
    erl_var = Context.source_var(context, source_index, field)

    {binding_vars, context} =
      Enum.reduce((index + (length - 1))..index, {{nil, 1}, context}, fn i, {acc, context} ->
        {var, context} = Context.binding_var(context, i)
        {{:cons, 1, {:var, 1, var}, acc}, context}
      end)

    {{:call, 1, {:remote, 1, {:atom, 1, :lists}, {:atom, 1, :member}},
      [{:var, 1, erl_var}, binding_vars]}, context}
  end

  defp to_qlc(
         {:in, [], [{{:., [], [{:&, [], [source_index]}, field]}, [], []}, values]},
         context
       )
       when is_list(values) do
    erl_var = Context.source_var(context, source_index, field)
    {var, context} = Context.extra_binding(context, values)

    {{:call, 1, {:remote, 1, {:atom, 1, :lists}, {:atom, 1, :member}},
      [{:var, 1, erl_var}, {:var, 1, var}]}, context}
  end

  defp to_qlc(
         {op, [], [{{:., [], [{:&, [], [source_index]}, field]}, [], []}, {:^, [], [index]}]},
         context
       ) do
    erl_var = Context.source_var(context, source_index, field)
    {var, context} = Context.binding_var(context, index)
    {{:op, 1, to_qlc_op(op), {:var, 1, erl_var}, {:var, 1, var}}, context}
  end

  defp to_qlc(
         {op, [],
          [
            {{:., [], [{:&, [], [left_source_index]}, left_field]}, [], []},
            {{:., [], [{:&, [], [right_source_index]}, right_field]}, [], []}
          ]},
         context
       ) do
    left_erl_var = Context.source_var(context, left_source_index, left_field)
    right_erl_var = Context.source_var(context, right_source_index, right_field)
    {{:op, 1, to_qlc_op(op), {:var, 1, left_erl_var}, {:var, 1, right_erl_var}}, context}
  end

  defp to_qlc(
         {op, [], [{{:., [], [{:&, [], [source_index]}, field]}, [], []}, value]},
         context
       ) do
    erl_var = Context.source_var(context, source_index, field)
    {var, context} = Context.extra_binding(context, value)
    {{:op, 1, to_qlc_op(op), {:var, 1, erl_var}, {:var, 1, var}}, context}
  end

  defp to_qlc_op(:!=), do: :"=/="
  defp to_qlc_op(:<=), do: :"=<"
  defp to_qlc_op(op), do: op
end
