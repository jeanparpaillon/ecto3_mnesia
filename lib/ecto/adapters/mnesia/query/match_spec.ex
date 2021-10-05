defmodule Ecto.Adapters.Mnesia.Query.MatchSpec do
  alias Ecto.Adapters.Mnesia.Source
  alias Ecto.Query.BooleanExpr
  alias Ecto.Query.QueryExpr

  def query(select, joins, [source]) do
    q = fn
      filters ->
        fn params ->
          context = %{source: source, params: params}
          get_results(select, joins, filters, context)
        end
    end

    {:nocache, q}
  end

  def get_results(select, joins, wheres, %{source: %Source{table: table} = source} = context) do
    match_head = Source.ms_record_pattern(source) |> List.to_tuple()
    match_body = [:"$_"]

    with {:atomic, results} <-
           :mnesia.transaction(fn ->
             match_expression = [
               {
                 match_head,
                 match_conditions(select, joins, wheres, context),
                 match_body
               }
             ]

             :mnesia.select(table, match_expression)
             |> Enum.map(fn record ->
               case select do
                 nil ->
                   Tuple.delete_at(record, 0)

                 select ->
                   select.fields
                   |> Enum.map(fn
                     {{:., _type, [{:&, [], [_source_index]}, field]}, [], []} ->
                       elem(record, source.index[field])
                   end)
                   |> List.to_tuple()
               end
             end)
           end) do
      results
    end
  end

  def match_conditions(_select, _joins, wheres, context) do
    Enum.map(wheres, fn
      %BooleanExpr{expr: expr} ->
        to_ms(expr, context)
    end)
  end

  def sort([], _select, _sources) do
    fn results -> results end
  end

  def sort([order_by], _select, sources) do
    fn results ->
      Enum.reduce(order_by.expr, results, fn
        {order, {{:., [], [{:&, [], [source_index]}, field]}, [], []}}, results ->
          Enum.sort_by(
            results,
            fn record ->
              source = Enum.at(sources, source_index)

              elem(record, source.index[field] - 1)
            end,
            order
          )
      end)
    end
  end

  def answers(limit, offset) do
    fn results, params ->
      results =
        case offset do
          nil -> results
          %QueryExpr{expr: offset} -> Enum.drop(results, unbind_value(offset, %{params: params}))
        end

      results =
        case limit do
          nil -> results
          %QueryExpr{expr: limit} -> Enum.take(results, unbind_value(limit, %{params: params}))
        end

      results
    end
  end

  defp to_ms({:or, [], [a, b]}, context) do
    {:orelse, to_ms(a, context), to_ms(b, context)}
  end

  defp to_ms({:and, [], [a, b]}, context) do
    {:andalso, to_ms(a, context), to_ms(b, context)}
  end

  defp to_ms({:not, [], [expr]}, context) do
    {:not, to_ms(expr, context)}
  end

  defp to_ms(
         {:in, [], [{{:., [], [{:&, [], [_source_index]}, field]}, [], []}, value]},
         context
       ) do
    erl_var = Source.to_ms_var(context.source, field)
    values = unbind_value(value, context)

    Enum.reduce(values, {:orelse}, fn value, acc ->
      Tuple.insert_at(acc, 1, {:==, erl_var, value})
    end)
  end

  defp to_ms({:is_nil, [], [{{:., [], [{:&, [], [_source_index]}, field]}, [], []}]}, context) do
    erl_var = Source.to_ms_var(context.source, field)

    {:==, erl_var, nil}
  end

  defp to_ms(
         {op, [], [{{:., [], [{:&, [], [_source_index]}, field]}, [], []}, value]},
         context
       ) do
    erl_var = Source.to_ms_var(context.source, field)
    value = unbind_value(value, context)
    {op_to_ms(op), erl_var, value}
  end

  defp unbind_value({:^, [], [index]}, context) do
    Enum.at(context.params, index)
  end

  defp unbind_value({:^, [], [index, length]}, context) do
    Enum.map(index..(index + length), fn current ->
      Enum.at(context.params, current)
    end)
  end

  defp unbind_value(value, _context), do: value

  defp op_to_ms(:!=), do: :"/="
  defp op_to_ms(op), do: op
end
