defmodule Windshield.ThirdApis do
  @moduledoc """
  Handles third party apis as Slack, Telegram, Twilio etc.
  """

  use Tesla

  plug(Tesla.Middleware.JSON)

  plug(Tesla.Middleware.Timeout, timeout: 8_000)

  def slack_post(slack_hook_url, channel, username, icon, text) do
    data = %{
      "channel" => channel,
      "username" => username,
      "text" => text,
      "icon_emoji" => icon
    }

    post(slack_hook_url, data)
  end
end
