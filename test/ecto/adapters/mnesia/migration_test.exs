defmodule Ecto.Adapters.Mnesia.MigrationTest do
  use Ecto.Adapters.Mnesia.RepoCase, async: false

  alias Ecto.Adapters.Mnesia.Migration
  alias Ecto.Adapters.Mnesia.Source

  defmodule SimpleSchema do
    use Ecto.Schema

    schema "test" do
      field(:field, :string)

      timestamps()
    end
  end

  defmodule KeysSourceSchema do
    use Ecto.Schema

    @primary_key false
    schema "test" do
      field(:key1, :id, primary_key: true, source: :source_key1)
      field(:key2, :id, primary_key: true)
      field(:field, :string, source: :source_field)

      timestamps()
    end

    def __record_name__, do: :alt_record
  end

  test "SimpleSchema" do
    ret = Migration.build_options(Source.new(%{schema: SimpleSchema}), [])
    assert %{attributes: [:id, :field, :inserted_at, :updated_at]} = Map.new(ret)
  end

  test "SimpleSchema - additional options" do
    ret =
      Migration.build_options(
        Source.new(%{schema: SimpleSchema}),
        index: [:field]
      )

    assert %{
             record_name: SimpleSchema,
             attributes: [:id, :field, :inserted_at, :updated_at],
             index: [:field]
           } = Map.new(ret)
  end

  test "KeysSourceSchema" do
    ret = Migration.build_options(Source.new(%{schema: KeysSourceSchema}), [])

    assert %{
             record_name: :alt_record,
             index: index,
             attributes: [:__key__, :source_key1, :key2, :source_field, :inserted_at, :updated_at]
           } = Map.new(ret)

    assert [] == index -- [:source_key1, :key2]
  end
end
