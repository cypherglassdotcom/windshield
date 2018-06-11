defmodule WindshieldWeb.RootController do
  use WindshieldWeb, :controller

  alias WindshieldWeb.ErrorView

  alias Windshield.PrincipalMonitor
  alias Windshield.Node
  alias Windshield.Alerts
  alias Windshield.SystemAuth

  def health_check(conn, _params) do
    json(conn, "OK")
  end

  def version(conn, _params) do
    json(conn, Mix.Project.config[:version])
  end

  def monitor_state(conn, _params) do
    {:ok, state} = PrincipalMonitor.get_state()

    json(conn, state)
  end

  def node_state(conn, %{"account" => account}) do
    {:ok, state} = account |> String.to_atom() |> Node.get_state()
    json(conn, state)
  end

  def producers(conn, _params) do
    {:ok, producers} = PrincipalMonitor.get_producers()

    json(conn, producers)
  end

  def test_email(conn, _params) do
    Alerts.alert_mail("TEST_EMAIL", "WINDSHIELD Test email from /api/test-email")
    json(conn, "OK")
  end

  def test_slack(conn, _params) do
    Alerts.alert_slack("TEST_SLACK", "WINDSHIELD Test Slack from /api/test-slack")
    json(conn, "OK")
  end

  def auth(conn, params) do
    case SystemAuth.authenticate(conn, params["password"]) do
      {:ok, token} ->
        json(conn, token)

      {:error, reason} ->
        conn
        |> put_status(403)
        |> render(ErrorView, "500.json", reason: reason)
    end
  end
end
