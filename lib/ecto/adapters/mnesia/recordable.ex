defprotocol Ecto.Adapters.Mnesia.Recordable do
  @moduledoc """
  Defines a protocol for mapping structure to record
  """
  @fallback_to_any true

  alias Ecto.Adapters.Mnesia.Record
  alias Ecto.Adapters.Mnesia.Source

  @doc """
  Returns record name for the given schema.
  """
  @spec record_name(t()) :: atom()
  def record_name(struct)

  @doc """
  Returns record as field name/value enum

  Struct allows for identifying schema, and contain no useful data.
  """
  @spec load(struct, Record.t(), Source.t()) :: Enumerable.t()
  def load(struct, record, context)

  @doc """
  Returns parameters as record's attributes list

  Struct allows for identifying schema, and contain no useful data.
  """
  @spec dump(t(), Keyword.t(), Source.t()) :: list()
  def dump(struct, params, context)
end

defimpl Ecto.Adapters.Mnesia.Recordable, for: Any do
  alias Ecto.Adapters.Mnesia.Table

  def record_name(%{__struct__: schema}), do: schema

  def load(_struct, record, %{table: table_name}) do
    field_names = Table.attributes(table_name)

    field_values =
      record
      |> Tuple.to_list()
      |> List.delete_at(0)

    Enum.zip([field_names, field_values])
  end

  def dump(_struct, params, %{table: table_name}) do
    Table.attributes(table_name)
    |> Enum.map(fn attribute ->
      case Keyword.fetch(params, attribute) do
        {:ok, value} -> value
        :error -> nil
      end
    end)
  end
end
