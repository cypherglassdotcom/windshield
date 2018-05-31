defmodule Windshield.SystemAuth do
  @moduledoc """
  Manages the System Authentication to change settings and handle nodes
  """

  def authenticate(conn, password) do
    if password == system_password() do
      {:ok, %{token: Phoenix.Token.sign(conn, system_salt(), system_user()), user: system_user()}}
    else
      {:error, "Invalid Password"}
    end
  end

  def verify(socket, token) do
    case Phoenix.Token.verify(socket, system_salt(), token, max_age: 86_400) do
      {:ok, user_id} -> {:ok, user_id}
      {:error, reason} -> {:error, reason}
    end
  end

  def system_user do
    :windshield
    |> Application.get_env(__MODULE__)
    |> Keyword.get(:user)
  end

  def system_password do
    :windshield
    |> Application.get_env(__MODULE__)
    |> Keyword.get(:password)
  end

  def system_salt do
    :windshield
    |> Application.get_env(__MODULE__)
    |> Keyword.get(:salt)
  end
end
