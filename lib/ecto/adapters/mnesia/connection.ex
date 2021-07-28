defmodule Ecto.Adapters.Mnesia.Connection do
  @moduledoc false
  use GenServer

  alias Ecto.Adapters.Mnesia
  alias Ecto.Adapters.Mnesia.Connection
  alias Ecto.Adapters.Mnesia.Constraint

  @id_seq_table_name :mnesia_id_seq

  def start_link(config) do
    Connection
    |> GenServer.start_link([config], name: __MODULE__)
    |> case do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl GenServer
  def init(config) do
    {:ok, config}
  end

  @impl GenServer
  def terminate(_reason, state) do
    try do
      :dets.sync(@id_seq_table_name)
      state
    rescue
      e -> e
    end
  end

  def id_seq_table_name, do: @id_seq_table_name

  def id_seq(source), do: {@id_seq_table_name, source}

  def all(type, %Ecto.Query{} = query) do
    Mnesia.Query.from_ecto_query(type, query)
  end

  def ensure_id_seq_table(nil) do
    ensure_id_seq_table([node()])
  end

  def ensure_id_seq_table(nodes) when is_list(nodes) do
    case :mnesia.create_table(@id_seq_table_name,
           disc_copies: nodes,
           attributes: [:id, :seq],
           type: :set,
           storage_properties: [dets: [auto_save: 5_000]],
           load_order: 100
         ) do
      {:atomic, :ok} ->
        :mnesia.wait_for_tables([@id_seq_table_name], 1_000)

      {:aborted, {:already_exists, @id_seq_table_name}} ->
        :ok
    end
  end

  def ensure_constraints_table(nil) do
    ensure_constraints_table([node()])
  end

  def ensure_constraints_table(nodes) when is_list(nodes) do
    Constraint.ensure_table(nodes)
  end
end
