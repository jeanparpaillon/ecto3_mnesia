defmodule Ecto.Adapters.Mnesia.Query do
  @moduledoc false

  require Qlc

  alias Ecto.Query.BooleanExpr
  alias Ecto.Adapters.Mnesia
  alias Ecto.Adapters.Mnesia.Query
  alias Ecto.Adapters.Mnesia.Record
  alias Ecto.Adapters.Mnesia.Source
  alias Ecto.Query.QueryExpr

  defstruct original: nil,
            type: nil,
            sources: nil,
            query: nil,
            sort: nil,
            answers: nil,
            new_record: nil

  @type t :: %__MODULE__{
          original: Ecto.Query.t(),
          type: :all | :update_all | :delete_all,
          sources: [Source.t()],
          query: (params :: list() -> query_handle :: :qlc.query_handle()),
          sort: (query_handle :: :qlc.query_handle() -> query_handle :: :qlc.query_handle()),
          answers: (query_handle :: :qlc.query_handle(), context :: Keyword.t() -> list(tuple())),
          new_record: (tuple(), list() -> tuple())
        }

  @spec from_ecto_query(type :: atom(), ecto_query :: Ecto.Query.t()) ::
          mnesia_query :: t()
  def from_ecto_query(
        type,
        %Ecto.Query{
          sources: sources,
          updates: updates
        } = original
      ) do
    sources = sources(sources)
    {query, sort, answers} = build_query(original)
    new_record = new_record(Enum.at(sources, 0), updates)

    %Mnesia.Query{
      original: original,
      type: type,
      sources: sources,
      query: query,
      sort: sort,
      answers: answers,
      new_record: new_record
    }
  end

  defp build_query(
         %Ecto.Query{
           select: select,
           joins: joins,
           sources: sources,
           wheres: wheres,
           order_bys: order_bys,
           limit: limit,
           offset: offset
         } = original
       ) do
    sources = sources(sources)

    case get_query?(original) do
      true ->
        {
          Query.Get.query(select, joins, sources).(wheres),
          Query.Get.sort(order_bys, select, sources),
          Query.Get.answers(limit, offset)
        }

      false ->
        {
          Query.Qlc.query(select, joins, sources).(wheres),
          Query.Qlc.sort(order_bys, select, sources),
          Query.Qlc.answers(limit, offset)
        }
    end
  end

  defp get_query?(%Ecto.Query{
         select: select,
         sources: {source},
         wheres: [where]
       }) do
    [source] = sources({source})

    case source.schema.__schema__(:primary_key) do
      [pk] ->
        !join_query?(select) &&
          pk_query?(where, pk)

      _ ->
        false
    end
  end

  defp get_query?(_), do: false

  defp join_query?(%Ecto.Query.SelectExpr{fields: fields}) do
    Enum.any?(fields, fn
      ({{:., [type: :id], _}, [], []}) -> true
      _ -> false
    end)
  end

  defp join_query?(_), do: false

  defp pk_query?(
         %BooleanExpr{
           expr:
             {:==, [],
              [{{:., [], [{:&, [], [_source_index]}, field]}, [], []}, {:^, [], [_index]}]}
         },
         pk
       )
       when field == pk,
       do: true

  defp pk_query?(_, _), do: false

  defp sources(sources) do
    sources
    |> Tuple.to_list()
    |> Enum.map(&Source.new/1)
  end

  defp new_record(source, updates) do
    fn tuple, params ->
      record = Record.new(tuple, source)

      params =
        params |> Enum.with_index() |> Enum.reduce(%{}, fn {p, i}, acc -> Map.put(acc, i, p) end)

      case updates do
        [%QueryExpr{expr: [set: replacements]}] ->
          replacements
          |> Enum.reduce(record, fn {field, {:^, [], [param_index]}}, acc ->
            Record.update(acc, [{field, Map.get(params, param_index)}], source)
          end)

        _ ->
          record
      end
    end
  end
end
