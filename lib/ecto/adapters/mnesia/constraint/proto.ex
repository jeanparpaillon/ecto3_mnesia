defprotocol Ecto.Adapters.Mnesia.Constraint.Proto do
  @moduledoc """
  Protocol for constraints
  """
  alias Ecto.Adapters.Mnesia.Constraint

  @doc """
  Returns nil if constraint is valid
  """
  @spec check(t(), Keyword.t()) :: :ok | {:error, Constraint.constraint()}
  def check(c, params)

  @doc """
  Returns constraint table
  """
  @spec table(t()) :: atom()
  def table(c)
end
