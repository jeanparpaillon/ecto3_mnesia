# Migration from 0.2 to 0.3

In order to migrate from O.2 to 0.3, you can run this following script, it will help to migrate mnesia tables and data to fit the new implementation:
- migrates `DateTime` fields to UNIX timestamps
- creates `:mnesia_constraints` table
- renames `:id_seq` table to `:mnesia_id_seq`

```elixir
defmodule Burellixyz.Ecto3MnesiaFrom022To030 do
  @naive_datetime_attributes [:inserted_at, :updated_at]

  def migrate(nodes, tables) do
    tables
    |> Enum.map(fn {table, naive_datetime_attributes} ->
      migrate_table_naive_datetime_to_unix(table, naive_datetime_attributes)
    end)

    migrate_id_seq(nodes, tables |> Enum.map(fn {table, _} -> table end))
    migrate_constraints(nodes)
  end

  def migrate_table_naive_datetime_to_unix(
        table,
        naive_datetime_attributes \\ @naive_datetime_attributes
      ) do
    attributes = :mnesia.table_info(table, :attributes)

    indexes =
      attributes
      |> Enum.with_index()
      |> Enum.filter(fn {attr, _} -> attr in naive_datetime_attributes end)
      |> Enum.map(fn {_, index} -> index end)
      |> IO.inspect()

    if Enum.count(indexes) !== 0 do
      :mnesia.transform_table(
        table,
        &transform_record_date_to_unix(&1, indexes),
        attributes
      )
    else
      :ok
    end
  end

  def migrate_constraints(nodes) do
    :mnesia.create_table(:mnesia_constraints,
      disc_copies: nodes,
      attributes: [:table, :constraint],
      type: :bag,
      storage_properties: [dets: [auto_save: 5_000]],
      load_order: 100
    )
  end

  def migrate_id_seq(nodes, tables) do
    if :id_seq in :mnesia.system_info(:tables) do
      max_id =
        :mnesia.dirty_all_keys(:id_seq)
        |> Enum.map(fn key -> :mnesia.dirty_read(:id_seq, key) end)
        |> List.flatten()
        |> Enum.reduce(1, fn {_, _, value}, max ->
          if value > max do
            value
          else
            max
          end
        end)
        |> IO.inspect()

      :mnesia.delete_table(:mnesia_id_seq)

      result =
        :mnesia.create_table(:mnesia_id_seq,
          disc_copies: nodes,
          attributes: [:id, :seq],
          type: :set,
          storage_properties: [dets: [auto_save: 5_000]],
          load_order: 100
        )

      case result do
        {:atomic, :ok} ->
          ok =
            tables
            |> Enum.map(fn table ->
              :mnesia.dirty_update_counter({:mnesia_id_seq, {table, :id}}, max_id)
            end)
            |> Enum.reduce(true, fn result, ok ->
              if not ok do
                ok
              else
                case result do
                  result when is_integer(result) -> true
                  _ -> false
                end
              end
            end)

          if ok do
            :mnesia.delete_table(:id_seq)
          else
            :ok
          end

        _ ->
          result
      end
    else
      :ok
    end
  end

  defp naive_datetime_to_unix(naive_datetime) do
    {:ok, date} = DateTime.from_naive(naive_datetime, "Etc/UTC")
    DateTime.to_unix(date)
  end

  defp transform_record_date_to_unix(record, indexes) do
    indexes
    |> Enum.reduce(record, fn index, record ->
      # firstone is the record_name
      index = index + 1

      case elem(record, index) do
        %NaiveDateTime{} = datetime ->
          unix = naive_datetime_to_unix(datetime)
          put_elem(record, index, unix)

        _ ->
          IO.inspect(
            {__MODULE__, "migrate_inserted_updated_date", "unable to convert", index, record}
          )

          record
      end
    end)
    |> IO.inspect()
  end
end
```
