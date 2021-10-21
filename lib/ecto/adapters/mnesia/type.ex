defmodule Ecto.Adapters.Mnesia.Type do
  @moduledoc false

  def dump_datetime(%DateTime{} = dt, precision) do
    {:ok, DateTime.to_unix(dt, precision)}
  end

  def dump_datetime(_, _), do: :error

  def dump_naive_datetime(%NaiveDateTime{} = dt, precision) do
    {:ok, dt |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_unix(precision)}
  rescue
    _ ->
      :error
  end

  def dump_naive_datetime(_, _), do: :error

  def dump_date(%Date{} = d) do
    {:ok, Date.to_gregorian_days(d)}
  end

  def dump_date(_), do: :error

  def dump_time(%Time{} = t) do
    {sec, _usec} = Time.to_seconds_after_midnight(t)
    {:ok, sec}
  end

  def dump_time(_), do: :error

  def dump_time_usec(%Time{} = t) do
    {sec, usec} = Time.to_seconds_after_midnight(t)
    {:ok, sec * 1_000_000 + usec}
  end

  def dump_time_usec(_), do: :error

  def load_datetime(i, precision) when is_integer(i) do
    {:ok, DateTime.from_unix!(i, precision)}
  end

  def load_datetime(_, _), do: :error

  def load_naive_datetime(i, precision) when is_integer(i) do
    {:ok, i |> DateTime.from_unix!(precision) |> DateTime.to_naive()}
  end

  def load_naive_datetime(_, _), do: :error

  def load_date(i) when is_integer(i) do
    {:ok, Date.from_gregorian_days(i)}
  end

  def load_date(_), do: :error

  def load_time(i) when is_integer(i) do
    {:ok, Time.from_seconds_after_midnight(i)}
  end

  def load_time(_), do: :error

  def load_time_usec(i) when is_integer(i) do
    sec = div(i, 1_000_000)
    usec = i - (sec * 1_000_000)

    {:ok, Time.from_seconds_after_midnight(sec, {usec, 6})}
  end

  def load_time_usec(_), do: :error
end
