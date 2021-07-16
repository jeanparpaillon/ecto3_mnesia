defmodule Ecto.Adapters.Mnesia.Constraint.ForeignKey do
  @moduledoc """
  Represents a foreignkey constraint
  """
  alias Ecto.Adapters.Mnesia.Source

  require Logger

  defstruct name: nil, from: nil, to: nil, fields: [], errors: []

  @type t :: %__MODULE__{
          name: String.t() | nil,
          from: Source.t() | nil,
          to: Source.t() | nil,
          fields: Keyword.t(),
          errors: [term()]
        }

  @type opt() :: {:name, String.t()}
  @type opts() :: [opt()]

  @doc """
  Returns newly created foreign key struct
  """
  @spec new(Source.t(), atom(), opts()) :: t()
  def new(from, rel, opts \\ [])

  def new(%Source{} = from, rel, opts) when is_atom(rel) and is_list(opts) do
    name =
      from.schema.__schema__(:association, rel)
      |> case do
        nil ->
          Keyword.fetch!(opts, :name)

        %Ecto.Association.BelongsTo{owner_key: col} ->
          Keyword.get_lazy(opts, :name, fn -> "#{from.table}_#{col}_fkey" end)
      end

    %__MODULE__{name: name, from: from}
    |> add_assoc(from.schema.__schema__(:association, rel))
  end

  def new(_, _, _) do
    %__MODULE__{errors: ["invalid arguments"]}
  end

  defp add_assoc(%{from: from, fields: fields} = c, %Ecto.Association.BelongsTo{} = a) do
    to = Source.new(%{schema: a.related})

    field =
      {from.schema.__schema__(:field_source, a.owner_key),
       to.schema.__schema__(:field_source, a.related_key)}

    %{c | to: to, fields: [field | fields]}
  end

  defimpl Ecto.Adapters.Mnesia.Constraint.Proto do
    alias Ecto.Adapters.Mnesia.Record

    def check(c, from_params) do
      c.fields
      |> Enum.reduce([], fn {from, to}, acc ->
        case Keyword.fetch(from_params, from) do
          {:ok, nil} -> acc
          {:ok, value} -> [{to, value} | acc]
          :error -> acc
        end
      end)
      |> case do
        [] ->
          :ok

        to_params ->
          pattern =
            c.to.match_all
            |> Record.update(to_params, c.to)

          case :mnesia.match_object(c.to.table, pattern, :read) do
            [] -> {:error, {:foreign_key, c.name}}
            _ -> :ok
          end
      end
    end

    def table(c), do: c.from.table
  end
end
