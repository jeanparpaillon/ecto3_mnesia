defmodule Ecto.Adapters.Mnesia.Migration do
  @moduledoc """
  Functions for dealing with schema migrations
  """
  alias Ecto.Adapters.Mnesia.Connection
  alias Ecto.Adapters.Mnesia.Constraint
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
  @type create_opt() ::
          access_opt()
          | disc_copies_opt()
          | disc_only_copies_opt()
          | index_opt()
          | load_order_opt()
          | majority_opt()
          | ram_copies_opt()
          | storage_properties_opt()
          | local_content_opt()
  @type create_opts() :: [create_opt()]
  @type sync_create_opts() :: [{:timeout, integer()} | create_opts()]

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
  @spec create_table(module(), module(), create_opts()) ::
          {:ok, table()} | :ignore | {:error, term()}
  def create_table(repo, schema, opts \\ []) when is_list(opts) do
    ensure_db_dir!(repo)
    ensure_schema(repo)

    source = Source.new(%{schema: schema})
    opts = build_options(source, opts)

    case :mnesia.create_table(source.table, opts) do
      {:atomic, :ok} -> {:ok, source.table}
      {:aborted, {:already_exists, _}} -> :ignore
      {:aborted, error} -> {:error, error}
    end
  end

  @doc """
  Creates table and wait for its creation
  """
  @spec sync_create_table(module(), module(), sync_create_opts()) :: :ok | {:error, term()}
  def sync_create_table(repo, schema, opts \\ []) when is_list(opts) do
    timeout = Keyword.get(opts, :timeout, 5_000)

    case create_table(repo, schema, opts) do
      {:ok, table} -> wait_for_table(table, timeout)
      :ignore -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Drop table

  Returns ok if table has been deleted or did not exist
  """
  @spec drop_table(module()) :: :ok | {:error, term()}
  def drop_table(schema) do
    %{table: table} = Source.new(%{schema: schema})

    table
    |> :mnesia.delete_table()
    |> case do
      {:atomic, :ok} -> :ok
      {:aborted, {:no_exists, ^table}} -> :ok
      {:aborted, reason} -> {:error, reason}
    end
  end

  @doc """
  Add a foreign key constraint
  """
  @spec references(module(), atom(), Constraint.ForeignKey.opts()) :: :ok | {:error, term()}
  def references(from, relation, opts \\ []) do
    %{schema: from}
    |> Source.new()
    |> Constraint.ForeignKey.new(relation, opts)
    |> case do
      %Constraint.ForeignKey{errors: []} = c -> Constraint.register(c)
      c -> {:error, c.errors}
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
      |> MapSet.to_list()

    [
      index: index,
      attributes: source.attributes,
      type: :ordered_set,
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
        :local_content,
        :type
      ])
    )
  end

  defp wait_for_table(table, timeout) do
    case :mnesia.wait_for_tables([table], timeout) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
      {:timeout, [table]} -> {:error, {:timeout, table}}
    end
  end

  defp ensure_db_dir!(repo) do
    repo_dir = repo.config()[:path]

    repo_dir =
      if repo_dir do
        Path.expand(repo_dir)
      else
        nil
      end

    mnesia_dir = :mnesia |> Application.get_env(:dir) |> to_string() |> Path.expand()

    if repo_dir && mnesia_dir != repo_dir do
      raise "Repo #{inspect(repo)} path is set to: #{repo_dir}. " <>
              "mnesia dir is set to: #{mnesia_dir}. " <>
              "Ensure Repo is started before calling `create_table`"
    end
  end

  defp ensure_schema(repo) do
    nodes = repo.config()[:nodes] || [node()]

    with id_seq when id_seq in [:ok, :already_exists] <- Connection.ensure_id_seq_table(nodes),
         cons when cons in [:ok, :alread_exists] <- Connection.ensure_constraints_table(nodes) do
      :ok
    end
  end
end
