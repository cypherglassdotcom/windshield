defmodule Windshield.Node do
  @moduledoc """
  GenServer that handles and watch a specific single node
  """

  use GenServer

  alias Windshield.Database
  alias Windshield.PrincipalMonitor
  alias Windshield.Alerts
  alias Windshield.EosApi

  @invalid_ping -1

  require Logger

  def start_link(options) do
    %{node: %{"account" => account}} = options
    GenServer.start_link(__MODULE__, options, name: String.to_atom(account))
  end

  def init(options) do
    Logger.info("#{inspect(options)} >>> Starting Node Watcher")

    %{node: node, settings: settings} = options

    %{
      "account" => account,
      "ip" => ip,
      "port" => port,
      "is_ssl" => is_ssl,
      "is_watchable" => is_watchable,
      "position" => position,
      "type" => type,
      "last_produced_block" => last_produced_block,
      "last_produced_block_at" => last_produced_block_at
    } = node

    name = String.to_atom(account)

    url = get_url(is_ssl, ip, port)

    state = %{
      name: name,
      account: account,
      ip: ip,
      port: port,
      is_ssl: is_ssl,
      url: url,
      is_watchable: is_watchable,
      type: type,
      position: position,
      status: :initial,
      bp_paused: false,
      last_info: nil,
      last_head_block_num: 0,
      lib_num: 0,
      head_producer: "",
      head_block_time: "",
      ping_stats: %{
        ping_ms: -1,
        ping_total_requests: 0,
        last_success_ping_at: -1,
        ping_total_failures: 0,
        ping_failures_since_last_success: 0
      },
      last_ping_alert_at: 0,
      last_bpcheck_alert_at: 0,
      last_unsynched_blocks_alert_at: 0,
      last_produced_block: last_produced_block,
      last_produced_block_at: last_produced_block_at,
      votes_count: 0,
      vote_position: 9999,
      vote_percentage: 0,
      vote_changed: 0,
      settings: settings
    }

    table = :ets.new(name, [:named_table, read_concurrency: true])
    :ets.insert(table, {"state", state})

    Logger.info("#{name} >>> Starting Node Initial state #{inspect(state)}")

    Process.send_after(self(), :node_loop, 2500)

    {:ok, state}
  end

  def handle_info(:node_loop, state) do
    {:ok, %{settings: settings}} = PrincipalMonitor.get_state()

    Logger.info("Node #{state.name} | #{state.status} | #{state.last_head_block_num}")

    GenServer.cast(state.name, :ping)

    # check block production if its a bp
    if state.type == "BP" && state.is_watchable do
      GenServer.cast(state.name, :bpcheck)
    end

    if state.account != settings["principal_node"] && state.is_watchable do
      GenServer.cast(state.name, :unsync_check)
    end

    new_state = %{state | settings: settings}
    :ets.insert(new_state.name, {"state", new_state})

    interval = state.settings["node_loop_interval"] || 501

    Process.send_after(self(), :node_loop, interval)

    {:noreply, new_state}
  end

  def handle_cast(:unsync_check, state) do
    %{settings: settings, last_unsynched_blocks_alert_at: last_unsynched_blocks_alert_at} = state

    principal_node_pid = String.to_atom(settings["principal_node"])

    case GenServer.call(principal_node_pid, :get_head_block) do
      {:ok, principal_head_block_num, _lib_num, _head_producer, _head_block_time} ->
        unsynched_blocks_to_alert = settings["unsynched_blocks_to_alert"]
        same_alert_interval_mins = settings["same_alert_interval_mins"]

        current_block_num = state.last_head_block_num

        unsync_blocks = principal_head_block_num - current_block_num

        last_unsynched_blocks_alert_diff = System.os_time() - last_unsynched_blocks_alert_at

        unsynched_blocks = unsync_blocks > unsynched_blocks_to_alert

        status =
          cond do
            state.status == :error ->
              :error

            unsynched_blocks && current_block_num > 0 ->
              :unsynched_blocks

            true ->
              :active
          end

        last_unsynched_blocks_alert_at =
          if unsynched_blocks && state.type != "EBP" && state.is_watchable &&
               last_unsynched_blocks_alert_diff > same_alert_interval_mins * 60_000_000_000 do
            error = """
            Node #{state.name} is out of sync with Principal Node #{settings["principal_node"]}.
            Current Node Block: #{current_block_num} - Current Principal Node Block: #{
              principal_head_block_num
            }
            - Unsynched blocks: #{unsync_blocks}
            """

            Database.insert_alert(Alerts.unsynched_blocks(), error, nil)
            System.os_time()
          else
            state.last_unsynched_blocks_alert_at
          end

        {:noreply,
         %{state | last_unsynched_blocks_alert_at: last_unsynched_blocks_alert_at, status: status}}

      _ ->
        {:noreply, state}
    end
  end

  def handle_cast(:bpcheck, state) do
    # check pause status
    bp_paused = check_bp_pause(state)

    # apply UTC timezone
    {last_produced_block_at, last_production_datetime} =
      calc_production_time(state.last_produced_block_at)

    same_alert_interval = state.settings["same_alert_interval_mins"] * 60_000_000_000

    last_production_diff_secs = (System.os_time() - last_production_datetime) / 1_000_000_000

    # do not alert if block production is paused
    last_bpcheck_alert_at =
      with false <- bp_paused,
           # should alert only if bp is under top 21
           true <- state.vote_position <= 21,
           true <- (System.os_time() - state.vote_changed) / 1_000_000_000 > state.settings["bp_tolerance_time_secs"],
           true <- state.is_watchable,
           true <- last_production_diff_secs > state.settings["bp_tolerance_time_secs"],
           last_bpcheck_alert_interval <- System.os_time() - state.last_bpcheck_alert_at,
           true <- last_bpcheck_alert_interval > same_alert_interval do
        error = """
        Block Producer Node #{state.name} is not producing for a while.
        Last Block production registered at #{last_produced_block_at} UTC.
        """

        Database.insert_alert(Alerts.bp_not_producing(), error, nil)
        System.os_time()
      else
        _ -> state.last_bpcheck_alert_at
      end

    {:noreply, %{state | last_bpcheck_alert_at: last_bpcheck_alert_at, bp_paused: bp_paused}}
  end

  def handle_cast(:ping, state) do
    {info_body, ping, error} = ping_info(state)

    # update last head block num
    {ping, last_head_block_num, lib_num, head_producer, head_block_time} =
      case info_body do
        %{
          "head_block_num" => num,
          "last_irreversible_block_num" => lib,
          "head_block_producer" => producer,
          "head_block_time" => block_time,
        } ->
          {ping, num, lib, producer, block_time}
        _ ->
          # if has invalid body, change the ping to invalid
          {@invalid_ping, state.last_head_block_num, state.lib_num, state.head_producer, state.head_block_time}

      end

    new_ping_stats = calc_ping_stats(state, ping)

    ping_failures = new_ping_stats.ping_failures_since_last_success

    {status, last_alert} =
      if ping == @invalid_ping && ping_failures > state.settings["failed_pings_to_alert"] do
        last_ping_alert =
          broadcast_ping_alert(
            state.settings["same_alert_interval_mins"],
            state.last_ping_alert_at,
            error,
            new_ping_stats,
            state.is_watchable
          )

        {:error, last_ping_alert}
      else
        broadcast_restored_ping(state)
        {:active, state.last_ping_alert_at}
      end

    # does not overwrite unsynched blocks
    status =
      if state.status == :unsynched_blocks && status == :active do
        :unsynched_blocks
      else
        status
      end

    new_state = %{
      state
      | status: status,
        ping_stats: new_ping_stats,
        last_info: info_body,
        last_ping_alert_at: last_alert,
        last_head_block_num: last_head_block_num,
        lib_num: lib_num,
        head_producer: head_producer,
        head_block_time: head_block_time
    }

    WindshieldWeb.Endpoint.broadcast("monitor:main", "tick_node", new_state)

    {:noreply, new_state}
  end

  def handle_cast({:update_produced_block, block_num, timestamp}, state) do
    new_produced_block = block_num
    new_produced_block_at = timestamp

    {last_produced_block_at, last_production_datetime} =
      calc_production_time(state.last_produced_block_at)

    {new_produced_block_at_txt, new_production_datetime} =
      calc_production_time(new_produced_block_at)

    if last_production_datetime < state.last_bpcheck_alert_at &&
         new_production_datetime > state.last_bpcheck_alert_at &&
         state.is_watchable do
      msg = """
      Block Producer Node #{state.name} came back at full steam production!
      New Block production registered at #{new_produced_block_at_txt} UTC,
      and the last one before that was #{last_produced_block_at}.
      """

      Database.insert_alert(Alerts.restored_production(), msg)
    end

    {:noreply,
     %{
       state
       | last_produced_block: new_produced_block,
         last_produced_block_at: new_produced_block_at
     }}
  end

  def handle_cast({:update_votes, votes_count, vote_percentage, bp_vote_position}, state) do

    vote_changed =
      if bp_vote_position <= 21 && state.vote_position > 21 do
        System.os_time()
      else
        state.vote_changed
      end

    new_state = %{
      state
      | votes_count: votes_count,
        vote_percentage: vote_percentage,
        vote_position: bp_vote_position,
        vote_changed: vote_changed
    }

    if new_state.vote_position != state.vote_position && state.vote_position > 0 &&
         state.vote_position != 9999 && state.is_watchable do
      msg = """
      The BP #{state.account} has changed the voting position rank
      from #{state.vote_position} to #{new_state.vote_position}.
      """

      alert_type =
        if new_state.vote_position < state.vote_position do
          Alerts.restored_voting_position()
        else
          Alerts.voting_position()
        end

      Database.insert_alert(alert_type, msg, nil)
    end

    {:noreply, new_state}
  end

  def handle_call(:get_head_block, _from, state) do
    {:reply, {:ok, state.last_head_block_num, state.lib_num, state.head_producer, state.head_block_time}, state}
  end

  def calc_ping_stats(state, ping) do
    ping_stats = state.ping_stats

    {ping_total_failures, last_success_ping_at, ping_failures_since_last_success} =
      if ping < 0 do
        {ping_stats.ping_total_failures + 1, ping_stats.last_success_ping_at,
         ping_stats.ping_failures_since_last_success + 1}
      else
        {ping_stats.ping_total_failures, System.os_time(), 0}
      end

    %{
      ping_stats
      | ping_ms: ping,
        ping_total_requests: state.ping_stats.ping_total_requests + 1,
        ping_total_failures: ping_total_failures,
        ping_failures_since_last_success: ping_failures_since_last_success,
        last_success_ping_at: last_success_ping_at
    }
  end

  def calc_production_time(last_prod_time) do
    # apply UTC timezone
    last_produced_block_at = last_prod_time <> "Z"

    last_production_datetime =
      case DateTime.from_iso8601(last_produced_block_at) do
        {:ok, datetime, 0} ->
          DateTime.to_unix(datetime) * 1_000_000_000

        {:error, _} ->
          0
      end

    {last_produced_block_at, last_production_datetime}
  end

  def ping_info(state) do
    start = System.os_time()

    case EosApi.get_chain_info(state.url) do
      {:ok, body} ->
        ping = System.os_time() - start
        {body, ping, nil}

      {:error, err} ->
        error = "#{state.name} >>> Fail to get #{state.url} CHAIN INFO\n #{inspect(err)}"
        Logger.error(error)
        {state.last_info, @invalid_ping, error}
    end
  end

  def check_bp_pause(state) do
    case EosApi.check_bp_pause(state.url) do
      {:ok, true} ->
        true

      {:ok, false} ->
        false

      # if error, retrieves the last status until it's recovered
      _ ->
        state.bp_paused
    end
  end

  def broadcast_ping_alert(
        same_alert_interval_mins,
        last_ping_alert_at,
        error,
        ping_stats,
        is_watchable
      ) do
    same_alert_interval = same_alert_interval_mins * 60_000_000_000
    last_ping_alert_diff = System.os_time() - last_ping_alert_at

    if last_ping_alert_diff > same_alert_interval && is_watchable do
      Database.insert_alert(Alerts.unanswered_ping(), error, ping_stats)
      System.os_time()
    else
      last_ping_alert_at
    end
  end

  def broadcast_restored_ping(state) do
    # only send alert if it had an error status before
    if state.status == :error && state.is_watchable do
      msg = "#{state.account} answered a successful ping and it's now restored!"
      Database.insert_alert(Alerts.restored_ping(), msg)
    end
  end

  def get_state(account) do
    try do
      [{"state", state}] = :ets.lookup(account, "state")
      {:ok, state}
    rescue
      e in ArgumentError ->
        Logger.error("Error selecting #{account} from Nodes state\n #{inspect(e)}")
        {:error, "State not found"}
    end
  end

  def get_url(is_ssl, ip, port) do
    is_ssl
    |> get_ssl_prefix()
    |> Kernel.<>(ip)
    |> Kernel.<>(":")
    |> Kernel.<>(Integer.to_string(port))
  end

  def get_ssl_prefix(is_ssl) do
    if is_ssl do
      "https://"
    else
      "http://"
    end
  end
end
