defmodule Ecto.Adapters.Mnesia.RepoCase do
  @moduledoc false
  use ExUnit.CaseTemplate

  alias Ecto.Adapters.Mnesia

  using do
    quote do
      alias EctoMnesia.TestRepo, as: Repo
    end
  end

  setup_all do
    options = %{path: "./mnesia.test"}

    ExUnit.CaptureLog.capture_log(fn ->
      case Mnesia.storage_up(options) do
        :ok -> :ok
        {:error, :already_up} -> :ok
      end
    end)

    {:ok, _repo} = EctoMnesia.TestRepo.start_link()

    on_exit fn ->
      Mnesia.storage_down(options)
    end

    %{options: options}
  end
end
