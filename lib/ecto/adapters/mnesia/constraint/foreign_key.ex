defmodule Ecto.Adapters.Mnesia.Constraint.ForeignKey do
  @moduledoc """
  Represents a foreignkey constraint
  """
  defstruct name: nil, from: nil, to: nil, type: nil, errors: []

  @type t :: %__MODULE__{
    name: String.t() | nil,
    from: {atom(), [atom()]} | nil,
    to: {atom(), [atom()]} | nil,
    type: atom() | nil,
    errors: [term()]
  }

  @type opt() :: {:name, String.t()} | {:column, atom()} | {:type, atom()}
  @type opts() :: [opt()]

  @doc """
  Returns newly created foreign key struct
  """
  @spec new({atom(), atom()}, atom(), opts()) :: t()
  def new(from, to, opts \\ [])

  def new({from, from_field}, to, opts) when is_atom(from) and is_atom(from_field) and is_atom(to) and is_list(opts) do
    name = Keyword.get_lazy(opts, :name, fn -> "#{from}_#{from_field}_fkey" end)
    to_field = Keyword.get(opts, :column, :id)
    type = Keyword.get(opts, :type, :id)

    %__MODULE__{
      name: name,
      from: {from, [from_field]},
      to: {to, [to_field]},
      type: type
    }
  end

  def new(_, _, _) do
    %__MODULE__{errors: ["invalid arguments"]}
  end
end
