defmodule WindshieldWeb.MonitorChannel do
  @moduledoc """
  Main websocket handler that deals with Windshield webapp
  """

  use Phoenix.Channel

  alias Windshield.PrincipalMonitor
  alias Windshield.Database
  alias Windshield.SystemAuth
  require Logger

  intercept(["tick_stats", "tick_producer", "tick_node", "emit_alert"])

  def join("monitor:main", _msg, socket) do
    {:ok, socket}
  end

  def handle_in("get_state", _payload, socket) do
    case PrincipalMonitor.get_state() do
      {:ok, state} -> push(socket, "get_state", state)
      _ -> push(socket, "get_state_fail", %{error: "Fail to get monitor state"})
    end

    {:noreply, socket}
  end

  def handle_in("get_settings", _payload, socket) do
    case Database.get_settings() do
      {:ok, data} -> push(socket, "get_settings", data)
      _ -> push(socket, "get_settings_fail", %{error: "Fail to get settings"})
    end

    {:noreply, socket}
  end

  def handle_in(
        "update_settings",
        %{
          "token" => token,
          "principal_node" => principal_node,
          "monitor_loop_interval" => monitor_loop_interval,
          "node_loop_interval" => node_loop_interval,
          "same_alert_interval_mins" => same_alert_interval_mins,
          "bp_tolerance_time_secs" => bp_tolerance_time_secs,
          "unsynched_blocks_to_alert" => unsynched_blocks_to_alert,
          "calc_votes_interval_secs" => calc_votes_interval_secs,
          "failed_pings_to_alert" => failed_pings_to_alert
        },
        socket
      ) do
    # authenticate user
    {:ok, _user} = SystemAuth.verify(socket, token)

    # pattern match to assure all fields
    settings = %{
      "principal_node" => principal_node,
      "monitor_loop_interval" => monitor_loop_interval,
      "node_loop_interval" => node_loop_interval,
      "same_alert_interval_mins" => same_alert_interval_mins,
      "bp_tolerance_time_secs" => bp_tolerance_time_secs,
      "unsynched_blocks_to_alert" => unsynched_blocks_to_alert,
      "calc_votes_interval_secs" => calc_votes_interval_secs,
      "failed_pings_to_alert" => failed_pings_to_alert
    }

    # validates principal node
    existent_node =
      if String.length(principal_node) > 0 do
        {:ok, res} = Database.get_node(principal_node)
        res
      else
        "any"
      end

    if existent_node == nil do
      push(socket, "update_settings_fail", %{
        error: "Principal Node #{principal_node} not registered"
      })
    else
      case Database.update_settings(settings) do
        {:ok, _} -> push(socket, "update_settings", settings)
        _ -> push(socket, "update_settings_fail", %{error: "Fail to update settings"})
      end
    end

    {:noreply, socket}
  end

  def handle_in("get_nodes", _payload, socket) do
    case Database.get_nodes() do
      {:ok, data} -> push(socket, "get_nodes", %{rows: data})
      _ -> push(socket, "get_nodes_fail", %{error: "Fail to get nodes"})
    end

    {:noreply, socket}
  end

  def handle_in("get_producers", _payload, socket) do
    case Database.get_producers() do
      {:ok, data} -> push(socket, "get_producers", %{rows: data})
      _ -> push(socket, "get_producers_fail", %{error: "Fail to get producers"})
    end

    {:noreply, socket}
  end

  def handle_in("get_alerts", _payload, socket) do
    case Database.get_alerts() do
      {:ok, data} -> push(socket, "get_alerts", %{rows: data})
      _ -> push(socket, "get_alerts_fail", %{error: "Fail to get alerts"})
    end

    {:noreply, socket}
  end

  def handle_in(
        "upsert_node",
        %{
          "token" => token,
          "account" => account,
          "ip" => ip,
          "port" => port,
          "is_ssl" => is_ssl,
          "is_watchable" => is_watchable,
          "type" => type
        },
        socket
      ) do
    # authenticate user
    {:ok, _user} = SystemAuth.verify(socket, token)

    cond do
      # String.length(account) != 12 ->
      #   push(socket, "upsert_node_fail", %{error: "Account must have 12 chars"})

      String.length(ip) < 7 ->
        push(socket, "upsert_node_fail", %{error: "Invalid IP"})

      true ->
        # only creates BlockProducers or FullNodes,
        # if is not recognized, set it as an External BP
        type =
          case type do
            "BP" -> "BP"
            "FN" -> "FN"
            _ -> "EBP"
          end

        with {:ok, new_node} <- Database.upsert_node(account, ip, port, is_ssl, is_watchable, type),
             {:ok, state} <- PrincipalMonitor.get_state() do

            if state.principal_node != nil do
              PrincipalMonitor.upsert_node(new_node)
            end

            push(socket, "upsert_node", new_node)
          else
            _ ->
              Logger.info("upsert_node_fail")
              push(socket, "upsert_node_fail", %{error: "Fail to upsert node"})
        end
    end

    {:noreply, socket}
  end

  def handle_out("tick_stats", stats, socket) do
    push(socket, "tick_stats", stats)
    {:noreply, socket}
  end

  def handle_out("tick_producer", producer, socket) do
    push(socket, "tick_producer", producer)
    {:noreply, socket}
  end

  def handle_out("emit_alert", alert, socket) do
    push(socket, "emit_alert", alert)
    {:noreply, socket}
  end

  def handle_out("tick_node", full_node, socket) do
    head_block_num =
      case full_node.last_info do
        %{"head_block_num" => head_block_num} -> head_block_num
        _ -> 0
      end

    ping_ms =
      case full_node.ping_stats do
        %{ping_ms: ping_ms} -> trunc(ping_ms / 1_000_000)
        _ -> -1
      end

    node = %{
      "account" => full_node.account,
      "ip" => full_node.ip,
      "port" => full_node.port,
      "is_ssl" => full_node.is_ssl,
      "is_watchable" => full_node.is_watchable,
      "type" => full_node.type,
      "head_block_num" => head_block_num,
      "last_produced_block" => full_node.last_produced_block,
      "last_produced_block_at" => full_node.last_produced_block_at,
      "ping_ms" => ping_ms,
      "status" => full_node.status,
      "votes_count" => full_node.votes_count,
      "vote_percentage" => full_node.vote_percentage
    }

    push(socket, "tick_node", node)
    {:noreply, socket}
  end
end
