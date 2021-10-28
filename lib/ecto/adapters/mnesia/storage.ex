defmodule Ecto.Adapters.Mnesia.Storage do
  @moduledoc false
  alias Ecto.Adapters.Mnesia.Config

  @id_seq_table_name :mnesia_id_seq
  @constraints_table :mnesia_constraints

  def status(options) do
    config = Config.new(options)

    if File.exists?(Path.join(config.path, "schema.DAT")) do
      :up
    else
      :down
    end
  end

  def down(options) do
    config = Config.new(options)

    Application.stop(:mnesia)

    case File.rm_rf(config.path) do
      {:ok, _} -> :ok
      {:error, posix, binary} -> {:error, {posix, binary}}
    end
  end

  def up(options) do
    config = Config.new(options)

    with {:status, :down} <- {:status, status(config)},
         {:stop, :ok} <- {:stop, ensure_stop_mnesia()},
         {:create, :ok} <- {:create, create_schema(config)} do
        :ok
    else
      {:status, :up} -> {:error, :already_up}
      {:create, {:error, :already_exists}} -> {:error, {:create, :already_exists}}
    end
  end

  def wait_for_tables(timeout) do
    :mnesia.wait_for_tables([@id_seq_table_name, @constraints_table], timeout)
  end

  ###
  ### Priv
  ###
  defp ensure_stop_mnesia do
    case Application.stop(:mnesia) do
      :ok -> :ok
      {:error, {:not_started, :mnesia}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp create_schema(config) do
    with {:create, :ok} <- {:create, :mnesia.create_schema(config.nodes)},
         {:start, {:ok, _}} <- {:start, Application.ensure_all_started(:mnesia)},
         {:id_seq, :ok} <- {:id_seq, create_id_seq_table(config)},
         {:constraints, :ok} <- {:constraints, create_constraints_table(config)} do
      :ok
    else
      {op, {:error, reason}} -> {:error, {op, reason}}
    end
  end

  defp create_id_seq_table(config) do
    case :mnesia.create_table(@id_seq_table_name,
           disc_copies: config.nodes,
           attributes: [:id, :seq],
           type: :set,
           storage_properties: [dets: [auto_save: 5_000]],
           load_order: 100
         ) do
      {:atomic, :ok} -> :ok
      {:aborted, reason} -> {:error, reason}
    end
  end

  defp create_constraints_table(config) do
    case :mnesia.create_table(@constraints_table,
           disc_copies: config.nodes,
           attributes: [:table, :constraint],
           type: :bag,
           storage_properties: [dets: [auto_save: 5_000]],
           load_order: 100
         ) do
      {:atomic, :ok} -> :ok
      {:aborted, reason} -> {:error, reason}
    end
  end
end
