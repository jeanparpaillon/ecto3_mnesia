defmodule Ecto.Adapters.Mnesia.Constraint do
  @moduledoc """
  Functions for checking records against constraints
  """
  alias Ecto.Adapters.Mnesia.Constraint.Proto
  alias Ecto.Adapters.Mnesia.Source

  import Record

  defrecord :mnesia_constraints, table: nil, constraint: nil

  @table :mnesia_constraints

  @type constraint() :: {:unique | :foreign_key | :exclusion | :check, String.t()}

  @doc """
  Check parameters against constraints.

  Returns eventually violated constraints
  """
  @spec check(Source.t(), Keyword.t()) :: [constraint()]
  def check(source, params) do
    source.table
    |> get()
    |> Enum.reduce([], fn mnesia_constraints(constraint: c), acc ->
      case Proto.check(c, params) do
        :ok -> acc
        {:error, reason} -> [reason | acc]
      end
    end)
  end

  @doc """
  Returns constraints for the given table
  """
  def get(table) do
    :mnesia.transaction(fn ->
      :mnesia.read(@table, table, :read)
    end)
    |> case do
      {:atomic, c} -> c
    end
  end

  @doc """
  Register a constraint
  """
  def register(constraint) do
    :mnesia.transaction(fn ->
      :mnesia.write(mnesia_constraints(table: Proto.table(constraint), constraint: constraint))
    end)
    |> case do
      {:atomic, c} -> c
    end
  end

  @doc """
  Ensure constraints table has been created
  """
  def ensure_table(nodes) do
    case :mnesia.create_table(@table,
           disc_copies: nodes,
           attributes: [:table, :constraint],
           type: :bag,
           storage_properties: [dets: [auto_save: 5_000]],
           load_order: 100
         ) do
      {:atomic, :ok} ->
        :mnesia.wait_for_tables([@table], 1_000)

      {:aborted, {:already_exists, @table}} ->
        :mnesia.wait_for_tables([@table], 1_000)
    end
  end
end
