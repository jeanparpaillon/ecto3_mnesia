defmodule EctoMnesia.TestRepo do
  @moduledoc false
  use Ecto.Repo,
    otp_app: :ecto3_mnesia,
    adapter: Ecto.Adapters.Mnesia
end
