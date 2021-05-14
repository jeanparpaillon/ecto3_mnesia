defmodule Ecto.Adapters.Mnesia.Migration do
  @moduledoc """
  Functions for dealing with schema migrations
  """
  alias Ecto.Adapters.Mnesia.Source

  @type table() :: atom()
  @type access_opt() :: {:access_mode, :read_write | :read_only}
  @type disc_copies_opt() :: {:disc_copies, [node()]}
  @type disc_only_copies_opt() :: {:disc_only_copies, [node()]}
  @type index_opt() :: {:index, [atom()]}
  @type load_order_opt() :: {:load_order, integer()}
  @type majority_opt :: {:majority, boolean()}
  @type ram_copies_opt :: {:ram_copies, [node()]}
  @type storage_properties_opt :: {:storage_properties, [{atom(), term()}]}
  @type local_content_opt :: {:local_content, boolean()}
  @type create_opts() :: [
          access_opt()
          | disc_copies_opt()
          | disc_only_copies_opt()
          | index_opt()
          | load_order_opt()
          | majority_opt()
          | ram_copies_opt()
          | storage_properties_opt()
          | local_content_opt()
        ]

  @doc """
  Creates mnesia table.

  See `http://erlang.org/doc/man/mnesia.html#create_table-2` for options, except
  from the following ones:
  * `attributes`: ignored, computed from schema
  * `index`: in addition to primary keys indices
  * `record_name`: ignored, computed from schema
  * `snmp`: unsupported
  * `type`: ignored, all tables are of type `set`


  Returns created table name
  """
  @spec create_table(module(), create_opts()) :: {:ok, table()} | :ignore | {:error, term()}
  def create_table(schema, opts \\ []) when is_list(opts) do
    source = Source.new(%{schema: schema})
    opts = build_options(source, opts)

    case :mnesia.create_table(source.table, opts) do
      {:atomic, :ok} -> {:ok, source.table}
      {:aborted, {:already_exists, _}} -> :ignore
      {:aborted, error} -> {:error, error}
    end
  end

  @doc false
  def build_options(source, opts) do
    extra_keys =
      case source.extra_key do
        nil -> []
        extra -> Map.keys(extra)
      end

    index =
      opts
      |> Keyword.get(:index, [])
      |> MapSet.new()
      |> MapSet.union(MapSet.new(extra_keys))
      |> Enum.reduce([], fn field, acc ->
        [source.schema.__schema__(:field_source, field) | acc]
      end)

    [
      index: index,
      attributes: source.attributes,
      type: :set,
      record_name: source.record_name
    ]
    |> Keyword.merge(
      Keyword.take(opts, [
        :access_mode,
        :disc_copies,
        :disc_copies_only,
        :load_order,
        :majority,
        :ram_copies,
        :storage_properties,
        :local_content
      ])
    )
  end
end
