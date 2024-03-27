defmodule Ecto.Adapters.Mnesia.StorageIntegrationTest do
  use ExUnit.Case

  alias Ecto.Adapters.Mnesia

  setup do
    tmp_dir = "./mnesia.test.#{:erlang.phash2(make_ref())}"
    options = %{path: tmp_dir}

    on_exit(fn ->
      Mnesia.storage_down(options)
    end)

    %{options: options}
  end

  describe "#storage_up" do
    test "should write mnesia files", %{options: options} do
      ExUnit.CaptureLog.capture_log(fn ->
        assert Mnesia.storage_up(options) == :ok
        assert File.exists?("./#{options.path}/schema.DAT")
      end)
    end

    test "should return an error if already up", %{options: options} do
      ExUnit.CaptureLog.capture_log(fn ->
        Mnesia.storage_up(options)
        assert Mnesia.storage_up(options) == {:error, :already_up}
      end)
    end
  end

  describe "#storage_down" do
    test "should down storage if up", %{options: options} do
      ExUnit.CaptureLog.capture_log(fn ->
        assert Mnesia.storage_down(options) == :ok
        refute File.exists?("./#{options.path}/schema.DAT")
      end)
    end

    test "storage_down returns :ok if already down", %{options: options} do
      ExUnit.CaptureLog.capture_log(fn ->
        Mnesia.storage_down(options)
        assert Mnesia.storage_down(options) == :ok
        refute File.exists?(options.path)
      end)
    end
  end

  describe "#storage_status (gives information only about the current node)" do
    test "should be down if storage down", %{options: options} do
      ExUnit.CaptureLog.capture_log(fn ->
        Mnesia.storage_down(options)
      end)

      assert Mnesia.storage_status(options) == :down
    end

    test "should be up if started", %{options: options} do
      ExUnit.CaptureLog.capture_log(fn ->
        Mnesia.storage_up(options)
      end)

      assert Mnesia.storage_status(options) == :up
    end
  end
end
