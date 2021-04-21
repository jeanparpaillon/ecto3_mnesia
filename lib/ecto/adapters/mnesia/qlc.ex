defmodule Ecto.Adapters.Mnesia.Qlc do
  @moduledoc false
  require Qlc

  alias Ecto.Adapters.Mnesia.Record
  alias Ecto.Adapters.Mnesia.Table
  alias Ecto.Query.BooleanExpr
  alias Ecto.Query.QueryExpr
  alias Ecto.Query.SelectExpr

  defmodule Context do
    @moduledoc false

    defstruct sources: [], params: [], qualifiers: [], joins: [], bindings: [], index: 0

    def new(%{sources: _, params: _} = args), do: struct(__MODULE__, args)
  end

  @order_mapping %{
    asc: :ascending,
    desc: :descending
  }

  @spec query(%SelectExpr{} | :all, any(), list(tuple())) ::
          (list() -> (params :: list() -> query_handle :: :qlc.query_handle()))
  def query(select, joins, sources) do
    select = select(select, sources)

    fn
      [%BooleanExpr{}] = wheres ->
        fn params ->
          context =
            %{sources: sources, params: params}
            |> Context.new()
            |> qualifiers(wheres)
            |> joins(joins)

          comprehension =
            [select, Enum.join(context.joins, ", "), Enum.join(context.qualifiers, ", ")]
            |> Enum.reject(fn component -> String.length(component) == 0 end)
            |> Enum.join(", ")

          Qlc.q("[#{comprehension}]", context.bindings)
        end

      filters ->
        fn params ->
          context =
            %{sources: sources, params: params}
            |> Context.new()
            |> qualifiers(filters)
            |> joins(joins)

          comprehension =
            [select, Enum.join(context.joins, ", "), Enum.join(context.qualifiers, ", ")]
            |> Enum.reject(fn component -> String.length(component) == 0 end)
            |> Enum.join(", ")

          Qlc.q("[#{comprehension}]", context.bindings)
        end
    end
  end

  @spec sort(list(%QueryExpr{}), %SelectExpr{}, list(tuple())) ::
          (query_handle :: :qlc.query_handle() -> query_handle :: :qlc.query_handle())
  def sort([], _select, _sources) do
    fn query -> query end
  end

  def sort(order_bys, select, sources) do
    fn query ->
      Enum.reduce(order_bys, query, fn
        %QueryExpr{expr: expr}, query1 ->
          Enum.reduce(expr, query1, fn {order, field_expr}, query2 ->
            field = field(field_expr, sources)
            field_index = Enum.find_index(fields(select, sources), fn e -> e == field end)

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

  defp select(select, sources) do
    fields = fields(select, sources)

    "{#{Enum.join(fields, ", ")}} || " <>
      (Enum.map(sources, fn {table_name, _schema} = source ->
         "#{record_pattern(source)} <- mnesia:table('#{table_name}')"
       end)
       |> Enum.join(", "))
  end

  defp fields(%SelectExpr{fields: fields}, sources) do
    Enum.flat_map(sources, fn _source ->
      Enum.map(fields, &field(&1, sources))
      |> Enum.reject(&is_nil(&1))
    end)
  end

  defp fields(:all, [{_table_name, schema} = source | _t]) do
    schema.__schema__(:fields)
    |> Enum.map(&Record.Attributes.to_erl_var(&1, source))
  end

  defp fields(_, [{_table_name, schema} = source | _t]) do
    schema.__schema__(:fields)
    |> Enum.map(&Record.Attributes.to_erl_var(&1, source))
  end

  defp field({{_, _, [{:&, [], [source_index]}, field]}, [], []}, sources) do
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

  defp record_pattern_attributes({table_name, _schema} = source) do
    Table.attributes(table_name)
    |> Enum.map(fn attribute -> Record.Attributes.to_erl_var(attribute, source) end)
    |> List.insert_at(0, "Schema")
  end

  defp to_qlc(true, context), do: {"true", context}

  defp to_qlc({field, value}, %{sources: [source]} = context) do
    erl_var = Record.Attributes.to_erl_var(field, source)
    {"#{erl_var} == #{to_erl(value)}", context}
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
    erl_var = Record.Attributes.to_erl_var(field, source)
    {"lists:member(#{erl_var}, [#{to_erl(values) |> Enum.join(", ")}])", context}
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
    erl_var = Record.Attributes.to_erl_var(field, source)
    value = to_erl(value)
    {"#{erl_var} =/= #{value}", context}
  end

  defp to_qlc(
         {op, [], [{{:., [], [{:&, [], [source_index]}, field]}, [], []}, value]},
         context
       ) do
    source = Enum.at(context.sources, source_index)
    erl_var = Record.Attributes.to_erl_var(field, source)
    value = to_erl(value)
    {"#{erl_var} #{op} #{value}", context}
  end

  defp to_erl(values) when is_list(values), do: Enum.map(values, &to_erl(&1))
  defp to_erl(value) when is_binary(value), do: inspect(value, binaries: :as_binaries)
  defp to_erl(value), do: value
end
