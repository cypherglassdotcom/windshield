defmodule Windshield.Mailer do
  @moduledoc "Mailing Helpers"

  use Bamboo.Mailer, otp_app: :windshield

  def sender do
    :windshield
    |> Application.get_env(__MODULE__)
    |> Keyword.get(:sender_email)
  end

  def recipients do
    :windshield
    |> Application.get_env(__MODULE__)
    |> Keyword.get(:recipients)
  end
end
