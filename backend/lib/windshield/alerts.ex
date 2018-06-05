defmodule Windshield.Alerts do
  @moduledoc """
  Submit alerts to outside systems via smtp, apis etc.
  """

  import Bamboo.Email

  alias Windshield.Mailer
  alias Windshield.ThirdApis
  import WindshieldWeb, only: [main_address: 0]

  @unanswered_ping "UNANSWERED_PING"
  @restored_ping "RESTORED_PING"
  @bp_not_producing "BP_NOT_PRODUCING"
  @restored_production "RESTORED_PRODUCTION"
  @unsynched_blocks "UNSYNCHED_BLOCKS"
  @voting_position "VOTING_POSITION"
  @restored_voting_position "RESTORED_VOTING_POSITION"
  @nodes_full_fork_report "NODES_FULL_FORK_REPORT"

  def unanswered_ping, do: @unanswered_ping
  def restored_ping, do: @restored_ping
  def bp_not_producing, do: @bp_not_producing
  def restored_production, do: @restored_production
  def unsynched_blocks, do: @unsynched_blocks
  def voting_position, do: @voting_position
  def restored_voting_position, do: @restored_voting_position
  def nodes_full_fork_report, do: @nodes_full_fork_report

  def alert_mail(type, description) do
    body = """
    <pre>#{description}</pre>

    <p>To see further details access
    <a href="#{main_address()}">Cypherglass WINDSHIELD here</a>!
    </p>

    <hr/>
    <em>This is an automatic message, please do not answer.</em>

    """

    new_email(
      to: Mailer.recipients(),
      from: Mailer.sender(),
      subject: "WINDSHIELD Alert: " <> type,
      html_body: body,
      text_body: body
    )
    |> Mailer.deliver_later()
  end

  def alert_slack(type, description) do
    text = """
    **WINDSHIELD Alert: #{type}**

    #{description}

    For more information <#{main_address()}|access Cypherglass WINDSHIELD here>.
    """

    ThirdApis.slack_post(slack_hook(), slack_channel(), slack_username(), slack_icon(), text)
  end

  def slack_hook do
    :windshield
    |> Application.get_env(:slack_alert)
    |> Keyword.get(:hook)
  end

  def slack_username do
    :windshield
    |> Application.get_env(:slack_alert)
    |> Keyword.get(:username)
  end

  def slack_channel do
    :windshield
    |> Application.get_env(:slack_alert)
    |> Keyword.get(:channel)
  end

  def slack_icon do
    :windshield
    |> Application.get_env(:slack_alert)
    |> Keyword.get(:icon)
  end
end
