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

    {:ok, settings} = Database.get_settings()

    state = %{
      name: name,
      loop: 0,
      status: :initial,
      settings: settings,
      stats: nil,
      block_processing: -1,
      current_block_head_num: -1,
      current_lib_num: -1,
      current_head_producer: "",
      principal_node: nil,
      principal_url: nil,
      nodes_pids: [],
      nodes: [],
      producers: [],
      last_calc_votes_at: 0,
      version: Mix.Project.config[:version]
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

    {:ok, nodes} = Database.get_nodes()
    nodes = nodes |> Enum.filter(fn n -> !n["is_archived"] end)

    stats = %{"id" => 1, "last_block" => 0, "lib" => 0}

    {:ok, producers} = Database.get_producers()

    nodes_details = merge_productions_to_nodes(nodes, producers)

    principal_node =
      nodes_details
      |> Enum.find(nil, fn n -> n["account"] == settings["principal_node"] end)

    {state, loop, loop_name} =
      if principal_node == nil do

        state = %{
          state
          | settings: settings,
            stats: stats,
            nodes: nodes_details,
            producers: producers
        }

        Logger.info("Principal Monitor Waiting for Principal Node Settings: #{inspect(state)}")

        {state, :load_settings, "Reload Settings"}
      else
        spawned_nodes =
          nodes_details
          |> Enum.map(fn n -> spawn_node(n, settings) end)

        principal_url =
          Node.get_url(principal_node["is_ssl"], principal_node["ip"], principal_node["port"])

        state = %{
          state
          | status: :active,
            settings: settings,
            stats: stats,
            principal_node: String.to_atom(principal_node["account"]),
            principal_url: principal_url,
            nodes_pids: spawned_nodes,
            nodes: nodes_details,
            producers: producers
        }

        Logger.info("Principal Monitor Settings Loaded: #{inspect(state)}")

        {state, :monitor_loop, "Starting Principal Loop"}
      end

    :ets.insert(state.name, {"state", state})

    monitor_loop_start = 10_000
    Process.send_after(self(), loop, monitor_loop_start)
    Logger.info("Principal Monitor #{loop_name} in: #{monitor_loop_start}")

    {:noreply, state}
  end

  def handle_info(:monitor_loop, state) do
    last_block = state.stats["last_block"]
    log_info(state, "Monitor Loop - #{state.status} | LB: #{last_block}")

    # refresh principal url
    state = %{state | principal_url: get_principal_url(state.principal_node)}

    # update blocks and sync
    new_state = initialize_block_processing(state)

    if (new_state.current_block_head_num != state.current_block_head_num) do
      tick_stats(new_state)
    end

    if (new_state.current_head_producer != state.current_head_producer) do
      tick_producer(new_state)
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

  def tick_stats(state) do
    stats =
      state.stats
      |> Map.put("status", state.status)
      |> Map.put("last_block", state.current_block_head_num)

    WindshieldWeb.Endpoint.broadcast("monitor:main", "tick_stats", stats)
  end

  def tick_producer(state) do
    WindshieldWeb.Endpoint.broadcast("monitor:main", "tick_producer", %{ producer: state.current_head_producer })
  end

  def initialize_block_processing(state) do
    with principal_node <- state.principal_node,
         {:ok, head_block_num, lib_num, head_producer, head_block_time} <- GenServer.call(principal_node, :get_head_block) do
      GenServer.cast(String.to_atom(head_producer), {:update_produced_block, head_block_num, head_block_time})
      %{ state | current_block_head_num: head_block_num, current_lib_num: lib_num, current_head_producer: head_producer}
    else
      _ -> state
    end
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
    try do
      [{"state", state}] = :ets.lookup(:principal_monitor, "state")
      {:ok, state}
    rescue
      e in ArgumentError ->
        Logger.error("principal_monitor >>> Fail to get State\n #{inspect(e)}")
        {:error, "State not found"}
    end
  end

  def get_principal_url(principal_node) do
    {:ok, node} = Node.get_state(principal_node)
    node.url
  end

  def respawn_node(node) do
    try do
      GenServer.call(:principal_monitor, {:respawn_node, node}, 30_000)
    catch
      :exit, _ -> :error
    end
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
    if node_pid != nil && GenServer.whereis(node_pid) != nil do
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
    {updated_nodes, updated_nodes_pids, principal_url} =
      if node["is_archived"] do
        log_info(state, "node #{node["account"]} was archived")
        {updated_nodes, updated_nodes_pids, state.principal_url}
      else
        node_details = [node] |> merge_productions_to_nodes(producers) |> hd()

        if settings["principal_node"] != "" do
          spawn_node(node_details, settings)
        end

        # update principal url in case it's respawning principal node
        principal_url =
          if node_pid_name == state.principal_node do
            Node.get_url(node["is_ssl"], node["ip"], node["port"])
          else
            state.principal_url
          end

        {[node_details | updated_nodes], [node_pid_name | nodes_pids], principal_url}
      end

    # tolerance time to wait for a next loop
    if settings["principal_node"] != "" do
      :timer.sleep(2_500 + settings["node_loop_interval"])
    end

    {:reply, :ok,
     %{state | nodes: updated_nodes, nodes_pids: updated_nodes_pids, principal_url: principal_url}}
  end
end
