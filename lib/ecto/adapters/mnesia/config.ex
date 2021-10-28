defmodule Ecto.Adapters.Mnesia.Config do
  @moduledoc false

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

  ###
  ### Priv
  ###
  defp set_path(%{path: path} = config) do
    Application.put_env(:mnesia, :dir, '#{path}', persistent: true)

    Map.merge(config, %{
      restart_mnesia: true
    })
  end

  defp set_path(%{} = config) do
    default_dir =
      case config do
        %{otp_app: otp_app} -> Application.app_dir(otp_app, "priv/mnesia")
        _ -> './priv/mnesia'
      end

    Map.merge(config, %{
      path: to_string(Application.get_env(:mnesia, :dir, default_dir)),
      restart_mnesia: false
    })
  end

  defp set_nodes(%{nodes: nodes} = config) when is_list(nodes),
    do: config

  defp set_nodes(config), do: Map.put(config, :nodes, [node()])
end
