defmodule Ecto.Adapters.Mnesia.Query do
  @moduledoc """
  This module is responsible for building a query out of an Ecto Query.

  Based on the complexity of the query, different translators can be used:
  * `Ecto.Adapters.Mnesia.Query.Get` for simple `Repo.get` -like queries
  * `Ecto.Adapters.Mnesia.Query.Qlc` for more complex ones
  """
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
            new_record: nil,
            cache: :nocache

  @type t :: %__MODULE__{
          original: Ecto.Query.t(),
          type: :all | :update_all | :delete_all,
          sources: [Source.t()],
          query: (params :: list() -> query_handle :: :qlc.query_handle()),
          sort: (query_handle :: :qlc.query_handle() -> query_handle :: :qlc.query_handle()),
          answers: (query_handle :: :qlc.query_handle(), context :: Keyword.t() -> list(tuple())),
          new_record: (tuple(), list() -> tuple()),
          cache: :nocache | :cache
        }

  defmodule ImplSelector do
    @moduledoc false
    defstruct single_pkey?: false, join_query?: false, pk_query?: false, pk: nil
  end

  @callback query(select :: term(), joins :: term(), sources :: term()) ::
              (params :: term() -> term())
  @callback sort(order_bys :: term(), select :: term(), sources :: term()) :: (term() -> term())
  @callback answers(limit :: term(), offset :: term()) ::
              (term(), context :: term() -> Enumerable.t())

  @spec from_ecto_query(type :: atom(), ecto_query :: Ecto.Query.t()) ::
          mnesia_query :: t()
  def from_ecto_query(
        type,
        %Ecto.Query{
          sources: sources,
          updates: updates,
          wheres: wheres,
          select: select,
          joins: joins,
          order_bys: order_bys,
          limit: limit,
          offset: offset
        } = original
      ) do
    sources = sources(sources)
    impl = select_impl(original)

    %Mnesia.Query{
      original: original,
      type: type,
      sources: sources,
      query: impl.query(select, joins, sources).(wheres),
      sort: impl.sort(order_bys, select, sources),
      answers: impl.answers(limit, offset),
      new_record: new_record(Enum.at(sources, 0), updates)
    }
  end

  @doc false
  def select_impl(original) do
    %ImplSelector{}
    |> single_pkey?(original)
    |> join_query?(original)
    |> pk_query?(original)
    |> case do
      %{single_pkey?: true, join_query?: false, pk_query?: true} -> Query.Get
      _ -> Query.Qlc
    end
  end

  defp single_pkey?(acc, %Ecto.Query{sources: {source}}) do
    with [source] <- sources({source}),
         [pk] <- source.schema.__schema__(:primary_key) do
      %{acc | single_pkey?: true, pk: pk}
    else
      _ ->
        %{acc | single_pkey?: false}
    end
  end

  defp single_pkey?(acc, _), do: %{acc | single_pkey?: false}

  defp join_query?(acc, %Ecto.Query{select: %Ecto.Query.SelectExpr{fields: fields}}) do
    Enum.any?(fields, fn
      {{:., [type: :id], _}, [], []} -> true
      _ -> false
    end)
    |> (&%{acc | join_query?: &1}).()
  end

  defp join_query?(acc, _), do: %{acc | join_query?: false}

  defp pk_query?(%{pk: pk} = acc, %Ecto.Query{
         wheres: [
           %BooleanExpr{
             expr:
               {:==, [],
                [{{:., [], [{:&, [], [_source_index]}, pk]}, [], []}, {:^, [], [_index]}]}
           }
         ]
       }) do
    %{acc | pk_query?: true}
  end

  defp pk_query?(acc, _), do: %{acc | pk_query?: false}

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
