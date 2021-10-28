defmodule Ecto.Adapters.Mnesia.Config do
  @moduledoc false
  require Logger

  @default %{timeout: 15_000}

  def new(config) when is_map(config) do
    @default
    |> Map.merge(config)
    |> set_path()
    |> set_nodes()
  end

  def new(options) when is_list(options) do
    new(Map.new(options))
  end

  def ensure_mnesia_config(config) do
    mnesia_dir = to_string(:mnesia.system_info(:directory))

    if config.path != mnesia_dir do
      Logger.info("Set mnesia storage directory")
      Application.stop(:mnesia)
      Application.put_env(:mnesia, :dir, '#{config.path}', persistent: true)
      {:ok, _} = Application.ensure_all_started(:mnesia)
    end

    config
  end

  ###
  ### Priv
  ###
  defp set_path(%{path: _path} = config), do: config

  defp set_path(%{} = config) do
    default_dir =
      case config do
        %{otp_app: otp_app} -> Application.app_dir(otp_app, "priv/mnesia")
        _ -> './priv/mnesia'
      end

    Map.merge(config, %{path: to_string(Application.get_env(:mnesia, :dir, default_dir))})
  end

  defp set_nodes(%{nodes: nodes} = config) when is_list(nodes),
    do: config

  defp set_nodes(config), do: Map.put(config, :nodes, [node()])
end
