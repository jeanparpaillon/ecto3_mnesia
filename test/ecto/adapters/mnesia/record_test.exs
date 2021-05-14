defmodule Ecto.Adapters.Mnesia.RecordTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.Mnesia.Record
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

  describe ".new(tuple)" do
    setup do
      simple = Source.new(%{schema: SimpleSchema, source: "test"})
      comp_key = Source.new(%{schema: CompKeySchema, source: "test"})
      [simple: simple, comp_key: comp_key]
    end

    test "simple", %{simple: source} do
      ret = Record.new({1, "field 1", nil, nil}, source)
      assert {SimpleSchema, 1, "field 1", nil, nil} = ret
    end

    test "compkey", %{comp_key: source} do
      ret = Record.new({{1, 2}, 1, 2, "field 1", nil, nil}, source)
      assert {CompKeySchema, {1, 2}, 1, 2, "field 1", nil, nil} = ret
    end
  end

  describe ".new(struct)" do
    setup do
      simple = Source.new(%{schema: SimpleSchema, source: "test"})
      keys = Source.new(%{schema: CompKeySchema, source: "test"})
      keys_source = Source.new(%{schema: KeysSourceSchema, source: "test"})
      [simple: simple, keys: keys, keys_source: keys_source]
    end

    test "simple", %{simple: source} do
      ret = Record.new(%SimpleSchema{id: 1, field: "field 1"}, source)
      assert {SimpleSchema, 1, "field 1", nil, nil} = ret
    end

    test "keys - incomplete keys", %{keys: source} do
      ret = Record.new(%CompKeySchema{key1: 1, field: "field 2"}, source)
      assert {CompKeySchema, {1, nil}, 1, nil, "field 2", nil, nil} = ret
    end

    test "keys - all keys", %{keys: source} do
      ret = Record.new(%CompKeySchema{key1: 1, key2: 2, field: "field 2"}, source)
      assert {CompKeySchema, {1, 2}, 1, 2, "field 2", nil, nil} = ret
    end

    test "keys / source mapped", %{keys_source: source} do
      ret = Record.to_schema({KeysSourceSchema, {1, 2}, 1, 2, "field", nil, nil}, source)
      assert %KeysSourceSchema{key1: 1, key2: 2, field: "field"} = ret
    end
  end

  describe ".to_schema" do
    setup do
      simple = Source.new(%{schema: SimpleSchema, source: "test"})
      keys = Source.new(%{schema: CompKeySchema, source: "test"})
      keys_source = Source.new(%{schema: KeysSourceSchema, source: "test"})
      [simple: simple, keys: keys, keys_source: keys_source]
    end

    test "simple", %{simple: source} do
      ret = Record.to_schema({SimpleSchema, 1, "field", nil, nil}, source)
      assert %SimpleSchema{id: 1, field: "field"} = ret
    end

    test "keys", %{keys: source} do
      ret = Record.to_schema({CompKeySchema, {1, 2}, 1, 2, "field", nil, nil}, source)
      assert %CompKeySchema{key1: 1, key2: 2, field: "field"} = ret
    end

    test "keys / source mapped", %{keys_source: source} do
      ret = Record.to_schema({KeysSourceSchema, {1, 2}, 1, 2, "field", nil, nil}, source)
      assert %KeysSourceSchema{key1: 1, key2: 2, field: "field"} = ret
    end
  end
end
