defmodule Ecto.Adapters.Mnesia do
  @behaviour Ecto.Adapter
  @behaviour Ecto.Adapter.Queryable

  alias Ecto.Adapters.Mnesia.Connection

  @impl Ecto.Adapter
  def __before_compile__(_env), do: true

  @impl Ecto.Adapter
  def checkout(_adapter_meta, _config, function) do
    function.()
  end

  @impl Ecto.Adapter
  def dumpers(:binary_id, type), do: [type, Ecto.UUID]
  def dumpers(_, type), do: [type]


  @impl Ecto.Adapter
  def ensure_all_started(_config, _type) do
    {:ok, _} = Application.ensure_all_started(:mnesia)
    {:ok, []}
  end

  @impl Ecto.Adapter
  def init(config) do
    {:ok, Connection.child_spec(), %{}}
  end

  @impl Ecto.Adapter
  def loaders(_primitive, type), do: [type]
end
