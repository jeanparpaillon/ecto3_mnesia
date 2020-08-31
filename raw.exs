require Qlc

defmodule TestSchema do
  defstruct id: nil, field: nil
end

:mnesia.start()

IO.inspect :mnesia.create_table(:test, [
  ram_copies: [node()],
  record_name: :test,
  attributes: [:id, :field],
  type: :ordered_set,
  index: [:field]
])

:mnesia.transaction fn ->
  Enum.map(1..1_000_000, fn (i) ->
    :mnesia.write(:test, {:test, i, "field #{i}"}, :write)
  end)
end

defmodule Test do
  require Qlc.Record

  Qlc.Record.defrecord(:test, [:id, :field])

  def query() do
    query1 = Qlc.q("[X || X <- mnesia:table(test), #{test!(X, :id)} == Field]", [Field: 1_000_000])
    query2 = Qlc.q("[X || X <- mnesia:table(test), #{test!(X, :field)} == Field]", [Field: "field 1000000"])
    query3 = Qlc.q("[[Id, Field] || {Schema, Id, Field} <- mnesia:table('test'), Field == Field2]", [Field2: "field 1000000"])

    IO.puts :qlc.info(query1)
    IO.puts :qlc.info(query2)
    IO.puts :qlc.info(query3)
    :mnesia.transaction fn ->
      IO.inspect :mnesia.read(:test, 1)
      IO.inspect :timer.tc(fn -> Qlc.e(query1) end)
      IO.inspect :timer.tc(fn -> Qlc.e(query2) end)
      IO.inspect :timer.tc(fn -> Qlc.e(query3) end)
    end
  end
end

IO.inspect Test.query()

# {:atomic, :ok}
# mnesia:table(test,
#              [{traverse,
#                {select,
#                 [{'$1',
#                   [{'==', {element, 2, '$1'}, {const, 1000000}}],
#                   ['$1']}]}},
#               {n_objects, 100},
#               {lock, read}])
# mnesia:table(test,
#              [{traverse,
#                {select,
#                 [{'$1',
#                   [{'==',
#                     {element, 3, '$1'},
#                     {const,
#                      <<102,105,101,108,100,32,49,48,48,48,48,48,48>>}}],
#                   ['$1']}]}},
#               {n_objects, 100},
#               {lock, read}])
# mnesia:table(test,
#              [{traverse,
#                {select,
#                 [{{'_', '$1', '$2'},
#                   [{'==', '$2',
#                     {const,
#                      <<102,105,101,108,100,32,49,48,48,48,48,48,48>>}}],
#                   [['$1', '$2']]}]}},
#               {n_objects, 100},
#               {lock, read}])
# [{:test, 1, "field 1"}]
# {265701, [{:test, 1000000, "field 1000000"}]}
# {302434, [{:test, 1000000, "field 1000000"}]}
# {303679, [[1000000, "field 1000000"]]}
