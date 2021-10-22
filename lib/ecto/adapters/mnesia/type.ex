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
    {:ok, to_gregorian_days(d)}
  end

  def dump_date(_), do: :error

  def dump_time(%Time{} = t) do
    {sec, _usec} = to_seconds_after_midnight(t)
    {:ok, sec}
  end

  def dump_time(_), do: :error

  def dump_time_usec(%Time{} = t) do
    {sec, usec} = to_seconds_after_midnight(t)
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
    {:ok, from_gregorian_days(i)}
  end

  def load_date(_), do: :error

  def load_time(i) when is_integer(i) do
    {:ok, from_seconds_after_midnight(i)}
  end

  def load_time(_), do: :error

  def load_time_usec(i) when is_integer(i) do
    sec = div(i, 1_000_000)
    usec = i - sec * 1_000_000

    {:ok, from_seconds_after_midnight(sec, {usec, 6})}
  end

  def load_time_usec(_), do: :error

  # Copy some functions introduced from elixir 1.11.0
  if Version.compare(System.version(), "1.11.0") in [:lt] do
    @seconds_per_day 24 * 60 * 60

    ###
    ### Time module
    ###
    defp to_seconds_after_midnight(%{microsecond: {microsecond, _precision}} = time) do
      iso_days = {0, to_day_fraction(time)}
      {Calendar.ISO.iso_days_to_unit(iso_days, :second), microsecond}
    end

    defp from_seconds_after_midnight(seconds, microsecond \\ {0, 0}, calendar \\ Calendar.ISO)
         when is_integer(seconds) do
      seconds_in_day = Integer.mod(seconds, @seconds_per_day)

      {hour, minute, second, {_, _}} =
        calendar.time_from_day_fraction({seconds_in_day, @seconds_per_day})

      %Time{
        calendar: calendar,
        hour: hour,
        minute: minute,
        second: second,
        microsecond: microsecond
      }
    end

    defp to_day_fraction(%{
           hour: hour,
           minute: minute,
           second: second,
           microsecond: {_, _} = microsecond,
           calendar: calendar
         }) do
      calendar.time_to_day_fraction(hour, minute, second, microsecond)
    end

    ###
    ### Date module
    ###
    defp to_gregorian_days(date) do
      {days, _} = to_iso_days(date)
      days
    end

    defp from_gregorian_days(days) when is_integer(days) do
      from_iso_days({days, 0}, Calendar.ISO)
    end

    defp to_iso_days(%{calendar: Calendar.ISO, year: year, month: month, day: day}) do
      {Calendar.ISO.date_to_iso_days(year, month, day), {0, 86_400_000_000}}
    end

    defp to_iso_days(%{calendar: calendar, year: year, month: month, day: day}) do
      calendar.naive_datetime_to_iso_days(year, month, day, 0, 0, 0, {0, 0})
    end

    defp from_iso_days({days, _}, Calendar.ISO) do
      {year, month, day} = Calendar.ISO.date_from_iso_days(days)
      %Date{year: year, month: month, day: day, calendar: Calendar.ISO}
    end
  else
    defdelegate to_seconds_after_midnight(t), to: Time
    defdelegate from_seconds_after_midnight(t), to: Time
    defdelegate from_seconds_after_midnight(t, usec), to: Time
    defdelegate from_seconds_after_midnight(t, usec, calendar), to: Time

    defdelegate to_gregorian_days(date), to: Date
    defdelegate from_gregorian_days(date), to: Date
    defdelegate from_gregorian_days(date, calendar), to: Date
  end
end
