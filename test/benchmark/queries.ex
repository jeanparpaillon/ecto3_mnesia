defmodule Ecto.Adapters.Mnesia.Benchmark.Queries do
  @moduledoc """
  Defines benchmark functions
  """
  alias Ecto.Adapters.Mnesia.Benchmark.Repo
  alias Ecto.Adapters.Mnesia.Benchmark.Schema
  alias Ecto.Adapters.Mnesia.Record
  alias Ecto.Adapters.Mnesia.Source
  alias :qlc_queries, as: Qlc

  @source Source.new(%{
            autogenerate_id: {:id, :id, :id},
            context: nil,
            prefix: nil,
            schema: Schema,
            source: "test_table"
          })

  @doc "ecto.get.id"
  def ecto_get_id(x) do
    item = Repo.get(Schema, x)
    validate!(item, x)
  end

  @doc "mnesia.get.id"
  def mnesia_get_id(x) do
    {:ok, item} =
      Repo.transaction(fn ->
        case :mnesia.read(:test_table, x) do
          [] -> nil
          [item] -> Record.to_schema(item, @source)
        end
      end)

    validate!(item, x)
  end

  @doc "qlc.get.id"
  def qlc_get_id(x) do
    {:ok, item} =
      Repo.transaction(fn ->
        case Qlc.get(:test_table, x) do
          [] -> nil
          [item] -> Record.to_schema(item, @source)
        end
      end)

    validate!(item, x)
  end

  @doc "ecto.get.int.idx"
  def ecto_get_int_idx(x) do
    item = Repo.get_by(Schema, indexed_int_field: x)

    validate!(item, x)
  end

  @doc "mnesia.get.int.idx"
  def mnesia_get_int_idx(x) do
    {:ok, item} =
      Repo.transaction(fn ->
        case :mnesia.index_read(:test_table, x, :indexed_int_field) do
          [] -> nil
          [item] -> Record.to_schema(item, @source)
        end
      end)

    validate!(item, x)
  end

  @doc "qlc.get.int.idx"
  def qlc_get_int_idx(x) do
    {:ok, item} =
      Repo.transaction(fn ->
        case Qlc.get_int_idx(:test_table, x) do
          [] -> nil
          [item] -> Record.to_schema(item, @source)
        end
      end)

    validate!(item, x)
  end

  @doc "ecto.get.string.idx"
  def ecto_get_string_idx(x) do
    item = Repo.get_by(Schema, indexed_field: "field-#{x}")

    validate!(item, x)
  end

  @doc "mnesia.get.string.idx"
  def mnesia_get_string_idx(x) do
    {:ok, item} =
      Repo.transaction(fn ->
        case :mnesia.index_read(:test_table, "field-#{x}", :indexed_field) do
          [] -> nil
          [item] -> Record.to_schema(item, @source)
        end
      end)

    validate!(item, x)
  end

  @doc "qlc.get.string.idx"
  def qlc_get_string_idx(x) do
    {:ok, item} =
      Repo.transaction(fn ->
        case Qlc.get_string_idx(:test_table, "field-#{x}") do
          [] -> nil
          [item] -> Record.to_schema(item, @source)
        end
      end)

    validate!(item, x)
  end

  @doc "ecto.get.int.non.idx"
  def ecto_get_int_non_idx(x) do
    item = Repo.get_by(Schema, non_indexed_int_field: x)

    validate!(item, x)
  end

  @doc "mnesia.get.int.non.idx"
  def mnesia_get_int_non_idx(x) do
    {:ok, item} =
      Repo.transaction(fn ->
        case :mnesia.match_object(:test_table, {:_, :_, :_, x, :_, :_, :_, :_}, :read) do
          [] -> nil
          [item] -> Record.to_schema(item, @source)
        end
      end)

    validate!(item, x)
  end

  @doc "qlc.get.int.non.idx"
  def qlc_get_int_non_idx(x) do
    {:ok, item} =
      Repo.transaction(fn ->
        case Qlc.get_int_non_idx(:test_table, x) do
          [] -> nil
          [item] -> Record.to_schema(item, @source)
        end
      end)

    validate!(item, x)
  end

  @doc "ecto.get.string.non.idx"
  def ecto_get_string_non_idx(x) do
    item = Repo.get_by(Schema, non_indexed_field: "field-#{x}")

    validate!(item, x)
  end

  @doc "mnesia.get.string.non.idx"
  def mnesia_get_string_non_idx(x) do
    {:ok, item} =
      Repo.transaction(fn ->
        case :mnesia.match_object(
               :test_table,
               {:_, :_, :_, :_, :_, "field-#{x}", :_, :_},
               :read
             ) do
          [] -> nil
          [item] -> Record.to_schema(item, @source)
        end
      end)

    validate!(item, x)
  end

  @doc "qlc.get.string.non.idx"
  def qlc_get_string_non_idx(x) do
    {:ok, item} =
      Repo.transaction(fn ->
        case Qlc.get_string_non_idx(:test_table, "field-#{x}") do
          [] -> nil
          [item] -> Record.to_schema(item, @source)
        end
      end)

    validate!(item, x)
  end

  defp validate!(%Schema{indexed_field: f} = record, x) do
    if f != "field-#{x}" do
      error!(record)
    else
      true
    end
  end

  defp validate!(record, _), do: error!(record)

  defp error!(record) do
    IO.puts("ERROR, got wrong value")
    # credo:disable-for-next-line
    IO.inspect(record)
    exit(1)
  end
end
