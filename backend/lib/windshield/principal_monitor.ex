defmodule Windshield.PrincipalMonitor do
  @moduledoc """
  GenServer that watch the main chain and orchestrate the nodes
  """

  use GenServer

  require Logger

  alias Windshield.Database
  alias Windshield.Node
  alias Windshield.EosApi
  alias Windshield.TaskVotesFork

  def start_link(options) do
    [name: name] = options
    GenServer.start_link(__MODULE__, name, name: name)
  end

  def init(name) do
    Logger.info("#{name} >>> Starting Principal Monitor")

    state = %{
      name: name,
      loop: 0,
      status: :initial,
      settings: nil,
      stats: nil,
      block_processing: -1,
      current_block_head_num: -1,
      principal_node: nil,
      principal_url: nil,
      nodes_pids: [],
      nodes: [],
      producers: [],
      last_calc_votes_at: 0
    }

    table = :ets.new(name, [:named_table, read_concurrency: true])
    :ets.insert(table, {"state", state})

    Logger.info("Principal Monitor initial state: #{inspect(state)}")

    loading_settings = 400
    Logger.info("Principal Monitor loading settings in : #{loading_settings}")
    Process.send_after(self(), :load_settings, loading_settings)

    {:ok, state}
  end

  def handle_info(:load_settings, state) do
    {:ok, settings} = Database.get_settings()

    if settings["principal_node"] == "" do
      Logger.info(
        "#{state.name} >>> Can't initialize the monitor without setting a principal node"
      )

      :timer.sleep(10_000)
      raise "Invalid Princpal Node in Settings"
    end

    {:ok, nodes} = Database.get_nodes()
    nodes = nodes |> Enum.filter(fn n -> !n["is_archived"] end)

    {:ok, stats} = Database.get_stats()

    {:ok, producers} = Database.get_producers()

    nodes_details = merge_productions_to_nodes(nodes, producers)

    principal_node =
      nodes_details
      |> Enum.find(nil, fn n -> n["account"] == settings["principal_node"] end)

    if principal_node == nil do
      Logger.info("#{state.name} >>> Invalid principal node #{settings["principal_node"]}")
      :timer.sleep(10_000)
      raise "Principal Node not Found from the one in Settings"
    end

    spawned_nodes =
      nodes_details
      |> Enum.map(fn n -> spawn_node(n, settings) end)

    principal_url =
      Node.get_url(principal_node["is_ssl"], principal_node["ip"], principal_node["port"])

    state = %{
      state
      | loop: 0,
        status: :active,
        settings: settings,
        stats: stats,
        block_processing: -1,
        current_block_head_num: -1,
        principal_node: String.to_atom(principal_node["account"]),
        principal_url: principal_url,
        nodes_pids: spawned_nodes,
        nodes: nodes_details,
        producers: producers,
        last_calc_votes_at: 0
    }

    :ets.insert(state.name, {"state", state})

    Logger.info("Principal Monitor Settings Loaded: #{inspect(state)}")

    monitor_loop_start = 10_000
    Process.send_after(self(), :monitor_loop, monitor_loop_start)
    Logger.info("Principal Monitor Starting monitor loop in: #{monitor_loop_start}")

    {:noreply, state}
  end

  def handle_info(:monitor_loop, state) do
    current_nodes = Enum.count(state.nodes)
    last_block = state.stats["last_block"]
    log_info(state, "Monitor Loop - #{state.status} | LB: #{last_block} | CN: #{current_nodes}")

    # refresh principal url
    state = %{state | principal_url: get_principal_url(state.principal_node)}

    # update blocks and sync
    new_state =
      case process_block_check(state) do
        {:syncing, principal_node, processing_block, current_block_head_num} ->
          new_state = %{
            state
            | status: :syncing,
              current_block_head_num: current_block_head_num,
              principal_node: principal_node
          }

          log_info(state, "Monitor Start Syncing...")
          new_state = process_block_loop(principal_node, processing_block, new_state)
          log_info(state, "Monitor End of Sync")

          new_state

        _ ->
          state
      end

    # check votes
    calc_votes_interval = state.settings["calc_votes_interval_secs"] * 1_000_000_000

    last_votes_check =
      if System.os_time() - state.last_calc_votes_at > calc_votes_interval &&
           new_state.current_block_head_num > 1 do
        # calc_votes(state)
        TaskVotesFork.init_report(
          new_state.principal_node,
          new_state.principal_url,
          new_state.current_block_head_num - 1
        )

        System.os_time()
      else
        state.last_calc_votes_at
      end

    # update new state
    {:ok, settings} = Database.get_settings()
    new_state = %{new_state | settings: settings, last_calc_votes_at: last_votes_check}
    :ets.insert(new_state.name, {"state", new_state})

    # schedule new loop
    interval = new_state.settings["monitor_loop_interval"] || 501
    Process.send_after(self(), :monitor_loop, interval)
    {:noreply, %{new_state | loop: state.loop + 1}}
  end

  def merge_productions_to_nodes(nodes, producers) do
    blank_producer = %{"last_produced_block" => 0, "last_produced_block_at" => ""}

    nodes
    |> Enum.map(fn node ->
      producer =
        producers
        |> Enum.find(blank_producer, fn producer ->
          producer["account"] == node["account"]
        end)

      node
      |> Map.put("last_produced_block", producer["last_produced_block"])
      |> Map.put("last_produced_block_at", producer["last_produced_block_at"])
    end)
  end

  def process_block_loop(principal_node, processing_block, state) do
    case GenServer.call(principal_node, {:get_block_info, processing_block}) do
      {:ok, info} ->
        # process block
        {new_stats, updated_producers} =
          do_process_block(state.stats, state.producers, processing_block, info)

        # update respective node
        GenServer.cast(String.to_atom(info["producer"]), {:update_block, info})

        # update state
        new_state = %{state | stats: new_stats, producers: updated_producers}

        # broadcast to websocket
        tick_stats = new_stats |> Map.put("status", state.status)
        WindshieldWeb.Endpoint.broadcast("monitor:main", "tick_stats", tick_stats)

        # update ets and log info
        :ets.insert(new_state.name, {"state", new_state})

        log_info(
          state,
          "Synched Producers: #{Enum.count(new_state.producers)} | Synched Last Block: #{
            new_state.stats["last_block"]
          }"
        )

        # recursive call to next process block
        {status, principal_node, processing_block, _} = process_block_check(new_state)

        if status == :syncing do
          process_block_loop(principal_node, processing_block, new_state)
        else
          %{
            new_state
            | status: status,
              principal_node: principal_node,
              block_processing: processing_block
          }
        end

      err ->
        # error, rollbacks to active status
        log_error(
          state,
          "Fail to get Block Info from #{principal_node}, Block num #{processing_block}, error:\n#{
            inspect(err)
          }"
        )

        %{state | block_processing: -1, status: :active}
    end
  end

  def initialize_block_processing(state) do
    with principal_node <- state.principal_node,
         {:ok, head_block_num} <- GenServer.call(principal_node, :get_head_block) do
      {head_block_num, principal_node}
    else
      _ -> {-1, nil}
    end
  end

  def process_block_check(state) do
    {current_block_head_num, principal_node} =
      case state.status do
        :active ->
          initialize_block_processing(state)

        :syncing ->
          {state.current_block_head_num, state.principal_node}
      end

    last_block = state.stats["last_block"]

    if current_block_head_num > last_block do
      processing_block = last_block + 1
      log_info(state, "Process Block checked new syncing block #{processing_block}")
      {:syncing, principal_node, processing_block, current_block_head_num}
    else
      {:active, principal_node, -1, current_block_head_num}
    end
  end

  def do_process_block(stats, producers, block_num, block_info) do
    block_producer = block_info["producer"]
    block_transactions = block_info["transactions"] |> Enum.count()

    blank_producer = %{
      "account" => block_producer,
      "blocks" => 0,
      "transactions" => 0,
      "last_produced_block" => 0,
      "last_produced_block_at" => ""
    }

    Logger.info("New Block to #{block_producer}: ##{block_num} | Txs: #{block_transactions}")

    new_producer =
      producers |> Enum.find(blank_producer, fn p -> p["account"] == block_producer end)

    new_producer = %{
      new_producer
      | "blocks" => new_producer["blocks"] + 1,
        "transactions" => new_producer["transactions"] + block_transactions,
        "last_produced_block" => block_info["block_num"],
        "last_produced_block_at" => block_info["timestamp"]
    }

    new_stats = %{stats | "last_block" => block_num}

    Database.update_producer(new_producer)
    Database.update_stats(new_stats)

    WindshieldWeb.Endpoint.broadcast("monitor:main", "tick_producer", new_producer)

    updated_producers =
      producers
      |> Enum.filter(fn p -> p["account"] != block_producer end)
      |> Kernel.++([new_producer])

    {new_stats, updated_producers}
  end

  def spawn_node(node, settings) do
    case Node.start_link(%{node: node, settings: settings}) do
      {:error, error} ->
        Logger.error(
          "An error happened while spawning node #{node["account"]} \n#{inspect(error)}"
        )

      {:ok, pid} ->
        Logger.info("Node #{node["account"]} spawned #{inspect(pid)}")
        String.to_atom(node["account"])
    end
  end

  def log_info(state, content), do: Logger.info("#{state.name}|#{state.loop} >>> #{content}")

  def log_error(state, content), do: Logger.error("#{state.name}|#{state.loop} >>> #{content}")

  def get_state do
    [{"state", state}] = :ets.lookup(:principal_monitor, "state")
    {:ok, state}
  end

  def get_principal_url(principal_node) do
    {:ok, node} = Node.get_state(principal_node)
    node.url
  end

  def respawn_node(node) do
    GenServer.call(:principal_monitor, {:respawn_node, node}, 30_000)
  end

  def get_producers do
    {:ok, state} = get_state()
    {:ok, state.producers}
  end

  def get_producers_table(state) do
    {status, producers_rows} =
      case EosApi.get_producers(state.principal_url) do
        {:ok, body} ->
          {:ok, body["rows"]}

        {:error, err} ->
          log_error(state, "Fail to get #{state.principal_url} PRODUCERS\n #{inspect(err)}")
          {:error, nil}
      end

    {status, producers_rows}
  end

  def handle_call(:get_state, _from, state) do
    {:reply, {:ok, state}, state}
  end

  def handle_call(:get_producers, _from, state) do
    {:reply, {:ok, state.producers}, state}
  end

  def handle_call({:respawn_node, node}, _from, state) do
    log_info(state, "(re)spawning node #{node["account"]}")

    %{nodes: nodes, producers: producers, nodes_pids: nodes_pids, settings: settings} = state

    node_pid_name = String.to_atom(node["account"])

    node_pid =
      nodes_pids
      |> Enum.find(fn n -> n == node_pid_name end)

    # stop node if needed and remove from list
    if node_pid != nil do
      log_info(state, "stopping #{node_pid}...")
      GenServer.stop(node_pid)
    end

    # remove node from actual state
    updated_nodes =
      nodes
      |> Enum.filter(fn n -> n["account"] != node["account"] end)

    updated_nodes_pids =
      nodes_pids
      |> Enum.filter(fn np -> np != node_pid_name end)

    # if it is archived, we are done, if not (re)spawn
    {updated_nodes, updated_nodes_pids} =
      if node["is_archived"] do
        log_info(state, "node #{node["account"]} was archived")
        {updated_nodes, updated_nodes_pids}
      else
        node_details = [node] |> merge_productions_to_nodes(producers) |> hd()
        spawn_node(node_details, settings)
        {[node_details | updated_nodes], [node_pid_name | nodes_pids]}
      end

    # tolerance time to wait for a next loop
    :timer.sleep(2_500 + settings["node_loop_interval"])

    {:reply, :ok, %{state | nodes: updated_nodes, nodes_pids: updated_nodes_pids}}
  end
end
