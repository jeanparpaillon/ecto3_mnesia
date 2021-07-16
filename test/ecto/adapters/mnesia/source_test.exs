defmodule Ecto.Adapters.Mnesia.SourceTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.Mnesia.Source

  defmodule SimpleSchema do
    use Ecto.Schema

    schema "test" do
      field(:field, :string)

      timestamps()
    end
  end

  defmodule CompKeySchema do
    use Ecto.Schema

    @primary_key false
    schema "test" do
      field(:key1, :id, primary_key: true)
      field(:key2, :id, primary_key: true)
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
  end

  describe ".new" do
    test "SimpleSchema" do
      ret = Source.new(%{schema: SimpleSchema, source: "test"})

      assert %Source{
               table: :test,
               attributes: [:id, :field, :inserted_at, :updated_at],
               default: {SimpleSchema, nil, nil, nil, nil},
               extra_key: nil
             } = ret
    end

    test "CompKeySchema" do
      ret = Source.new(%{schema: CompKeySchema, source: "test"})

      assert %Source{
               table: :test,
               attributes: [:__key__, :key1, :key2, :field, :inserted_at, :updated_at],
               default: {CompKeySchema, {nil, nil}, nil, nil, nil, nil, nil},
               extra_key: %{key1: 0, key2: 1}
             } = ret
    end

    test "KeysSourceSchema" do
      ret = Source.new(%{schema: KeysSourceSchema, source: "test"})

      assert %Source{
               table: :test,
               attributes: [
                 :__key__,
                 :source_key1,
                 :key2,
                 :source_field,
                 :inserted_at,
                 :updated_at
               ],
               default: {KeysSourceSchema, {nil, nil}, nil, nil, nil, nil, nil},
               extra_key: %{source_key1: 0, key2: 1}
             } = ret
    end
  end

  describe ".uniques" do
    setup do
      simple = Source.new(%{schema: SimpleSchema, source: "test"})
      comp_key = Source.new(%{schema: CompKeySchema, source: "test"})

      [simple: simple, comp_key: comp_key]
    end

    test "SimpleSchema - no params", %{simple: simple} do
      ret = Source.uniques(simple, [])
      assert [] = ret
    end

    test "SimpleSchema - key param", %{simple: simple} do
      ret = Source.uniques(simple, id: 1, field: "field 1")
      assert [id: 1] = ret
    end

    test "CompKeySchema - one key param", %{comp_key: comp_key} do
      ret = Source.uniques(comp_key, key2: 1, field: "field 1")
      assert [key2: 1] = ret
    end
  end
end
