defmodule Ecto.Adapters.Mnesia.Query.Get do
  @moduledoc """
  Query builder for simple `Repo.get` like queries
  """
  alias Ecto.Adapters.Mnesia.Query
  alias Ecto.Adapters.Mnesia.Source
  alias Ecto.Query.BooleanExpr

  @behaviour Query

  def query(_select, _joins, [%Source{table: table}]) do
    fn [
         %BooleanExpr{
           expr:
             {:==, [],
              [{{:., [], [{:&, [], [_source_index]}, _field]}, [], []}, {:^, [], [index]}]}
         }
       ] ->
      fn params ->
        :mnesia.read(table, Enum.at(params, index))
        |> Enum.map(fn record -> Tuple.delete_at(record, 0) end)
      end
    end
  end

  def sort(_orders_by, _select, _sources) do
    fn results -> results end
  end

  def answers(_limit, _offset) do
    fn results, _context -> results end
  end
end
