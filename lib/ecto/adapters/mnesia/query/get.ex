defmodule Ecto.Adapters.Mnesia.Query.Get do
  @moduledoc """
  Query builder for simple `Repo.get` like queries
  """
  alias Ecto.Adapters.Mnesia.Query
  alias Ecto.Adapters.Mnesia.Source
  alias Ecto.Query.BooleanExpr

  @behaviour Query

  def query(select, _joins, [source]) do
    q = fn [
             %BooleanExpr{
               expr: {:==, [], [{{:., [], [{:&, [], [_source_index]}, _field]}, [], []}, value]}
             }
           ] ->
      fn params ->
        pk = unbind(value, params)
        get_by_pk(source, pk, select)
      end
    end

    {:cache, q}
  end

  defp unbind({:^, [], [index]}, params), do: Enum.at(params, index)
  defp unbind(value, _params), do: value

  defp get_by_pk(%Source{table: table} = source, pk, select) do
    :mnesia.read(table, pk)
    |> Enum.map(fn record ->
      select.fields
      |> Enum.map(fn
        {{:., _type, [{:&, [], [_source_index]}, field]}, [], []} ->
          elem(record, source.index[field])
      end)
      |> List.to_tuple()
    end)
  end

  def sort(_orders_by, _select, _sources) do
    fn results -> results end
  end

  def answers(_limit, _offset) do
    fn results, _context -> results end
  end
end
