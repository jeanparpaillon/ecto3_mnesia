defmodule Ecto.Adapters.Mnesia.TypeTest do
  @moduledoc false
  use ExUnit.Case

  @adapter Ecto.Adapters.Mnesia

  test "UTC datetime" do
    dt = DateTime.utc_now() |> DateTime.truncate(:second)

    ret = Ecto.Type.adapter_dump(@adapter, :utc_datetime, dt)
    assert {:ok, ts} = ret

    ret = Ecto.Type.adapter_load(@adapter, :utc_datetime, ts)
    assert {:ok, ^dt} = ret
  end

  test "UTC datetime (µsec)" do
    dt = DateTime.utc_now()

    ret = Ecto.Type.adapter_dump(@adapter, :utc_datetime_usec, dt)
    assert {:ok, ts} = ret

    ret = Ecto.Type.adapter_load(@adapter, :utc_datetime_usec, ts)
    assert {:ok, ^dt} = ret
  end

  test "naive datetime" do
    dt = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    ret = Ecto.Type.adapter_dump(@adapter, :naive_datetime, dt)
    assert {:ok, ts} = ret

    ret = Ecto.Type.adapter_load(@adapter, :naive_datetime, ts)
    assert {:ok, ^dt} = ret
  end

  test "naive datetime (µsec)" do
    dt = NaiveDateTime.utc_now()

    ret = Ecto.Type.adapter_dump(@adapter, :naive_datetime_usec, dt)
    assert {:ok, ts} = ret

    ret = Ecto.Type.adapter_load(@adapter, :naive_datetime_usec, ts)
    assert {:ok, ^dt} = ret
  end

  test "date" do
    d = Date.utc_today()

    ret = Ecto.Type.adapter_dump(@adapter, :date, d)
    assert {:ok, ts} = ret

    ret = Ecto.Type.adapter_load(@adapter, :date, ts)
    assert {:ok, ^d} = ret
  end

  test "time" do
    t = Time.utc_now() |> Time.truncate(:second)

    ret = Ecto.Type.adapter_dump(@adapter, :time, t)
    assert {:ok, ts} = ret

    ret = Ecto.Type.adapter_load(@adapter, :time, ts)
    assert {:ok, ^t} = ret
  end

  test "time (µsec)" do
    t = Time.utc_now()

    ret = Ecto.Type.adapter_dump(@adapter, :time_usec, t)
    assert {:ok, ts} = ret

    ret = Ecto.Type.adapter_load(@adapter, :time_usec, ts)
    assert {:ok, ^t} = ret
  end
end
