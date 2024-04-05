defmodule Ecto.Adapters.MnesiaAdapterIntegrationTest do
  use ExUnit.Case, async: true

  alias Ecto.Adapters.Mnesia
  alias Ecto.Adapters.Mnesia.TestRepo, as: Repo

  setup do
    options = %{path: "./mnesia.test"}

    ExUnit.CaptureLog.capture_log(fn -> Mnesia.storage_up(options) end)
    Mnesia.ensure_all_started([], :permanent)

    on_exit(fn ->
      Mnesia.storage_down(options)
    end)

    :ok
  end

  describe "Ecto.Adapter#init" do
    test "#start_link" do
      {:ok, repo} = Repo.start_link()

      assert Process.alive?(repo)
    end
  end
end
