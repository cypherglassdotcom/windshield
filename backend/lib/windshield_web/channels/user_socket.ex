defmodule WindshieldWeb.UserSocket do
  use Phoenix.Socket

  ## Channels
  channel("monitor:*", WindshieldWeb.MonitorChannel)

  ## Transports
  transport(
    :websocket,
    Phoenix.Transports.WebSocket,
    check_origin: false
  )

  def connect(_params, socket) do
    {:ok, socket}
  end

  def id(_socket), do: nil

  def allowed_origins do
    :windshield
    |> Application.get_env(:cors_access)
    |> Keyword.get(:allowed_origins)
  end
end
