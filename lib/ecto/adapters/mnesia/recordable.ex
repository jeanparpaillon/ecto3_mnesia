defprotocol Ecto.Adapters.Mnesia.Recordable do
  @moduledoc """
  Defines a protocol for transforming structure to record
  """
  @fallback_to_any true

  @spec record_name(t()) :: atom()
  def record_name(struct)
end

defimpl Ecto.Adapters.Mnesia.Recordable, for: Any do
  def record_name(%{__struct__: schema}), do: schema
end
