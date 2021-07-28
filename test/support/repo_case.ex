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
    ExUnit.CaptureLog.capture_log(fn ->
      :ok = Mnesia.storage_down(nodes: [node()])

      case Mnesia.storage_up(nodes: [node()]) do
        :ok -> :ok
        {:error, :already_up} -> :ok
      end
    end)

    Mnesia.ensure_all_started([], :permanent)

    {:ok, _repo} = EctoMnesia.TestRepo.start_link()

    :ok
  end
end
