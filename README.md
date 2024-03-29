![Tests](https://github.com/jeanparpaillon/ecto3_mnesia/actions/workflows/ci.yml/badge.svg)

# Ecto Mnesia Adapter
This adapter brings the strength of Ecto providing validation, and persistance layer to interact to Mnesia databases.

Mnesia is Distributed Database Management System shipped with Erlang runtime. Be aware of strengths and weaknesses listed in [erlang documentation](https://erlang.org/doc/man/mnesia.html) and read the [known issues](#known-issues) to be sure the solution is adapted for your use case.


## What works
1. Queries
- [x] Basic all queries
- [x] Select queries
- [x] Simple where queries
- [x] and/or/in in where clauses
- [x] Bindings
- [ ] Fragments
- [x] Limit/Offset queries
- [x] Sort by one field
- [ ] Sort by multiple fields
- [x] One level joins
- [ ] Deeper joins

2. Writing operations
- [x] insert/insert_all
- [x] update/update_all
- [x] delete/delete_all
- [x] Auto incremented ids
- [x] Binary ids
- [ ] Delete without primary key
- [x] Unique constraint (primary keys)
- [ ] Unique constraint (arbitrary fields)
- [x] on_conflict (raise, nothing, replace)

3. Associations
- [x] has_one associations
- [x] has_many associations
- [x] belongs_to associations
- [ ] many_to_many associations

4. Transactions
- [x] Create transactions
- [x] Rollback transactions

## Instalation
You can include ecto3_mnesia in your dependencies as follow:
```
  defp deps do
    ...
    {:ecto3_mnesia, "~> 0.2.0"},
    ...
  end
```
Then configure your application repository to use Mnesia adapter as follow:
```
# ./lib/my_app/repo.ex
defmodule MyApp.Repo do
  use Ecto.Repo,
    otp_app: :my_app,
    adapter: Ecto.Adapters.Mnesia
end
```

## Migrations

`Ecto.Adapters.Mnesia.Migration.create_table/2` create mnesia table from an Ecto
schema module and mnesia specific options. Options like `attributes`, `type` or
`index` are inferred from schema.

### Record name

mnesia tables can have record name different from table name. By default, the
adapter use schema name (module name) as record name. For compatibility with
existing applications, one can customize record name per schema, by implementing
`__record_name__/0` function in the schema module.

```
defmodule MyApp.Schema do
  ...
  schema "table_name" do
    field :field, :string

    timestamps()
  end

  ...

  def __record_name__, do: :schema
end
```

## Known issues

- Delete queries using a select must include primary key (https://gitlab.com/patatoid/ecto3_mnesia/-/issues/9)
- Ecto 3.6 has introduced the possibility to send `placeholders` when using
  `Repo.insert_all` (see https://github.com/elixir-ecto/ecto_sql/pull/290).
  `placeholders` are not supported yet.
- This adapter is based mostly on erlang QLC, the bring quite a lot of overhead to queries and have performance issues.

## Migrate to 0.3

You can follow [these steps](guides/migrate_to_03.md) to migrate from 0.2 to 0.3 version as it provides some breaking changes.

## Tests
You can run the tests as any mix package running
```
git clone https://gitlab.com/patatoid/ecto3_mnesia.git
cd ecto3_mnesia
mix deps.get
mix test --trace
```

## Thanks
Many thanks to the contributors of ecto_sql and ecto_mnesia for their work on those topics that have inspired some of the design of this library

## Contributing
Contributions of any kind are welcome :)
