defmodule Windshield.TaskVotesFork do
  @moduledoc """
  Task for Execution of Votes Calculations and Generation of Fork Report
  """

  require Logger

  alias Windshield.EosApi
  alias Windshield.Node
  alias Windshield.Database
  alias Windshield.Alerts

  def init_report(principal_node, principal_url, block_num) do
    Task.start(__MODULE__, :calc_votes, [principal_node, principal_url, block_num])
  end

  def get_producers_table(principal_url, lower_bound \\ "") do
    Logger.info("Reading Producers Table Lower Bound: #{lower_bound}")
    case EosApi.get_producers(principal_url, lower_bound) do
      {:ok, body} ->
        if body["more"] do
          case get_producers_table(principal_url, List.last(body["rows"])["owner"]) do
            {:ok, next_body} -> {:ok, body["rows"] ++ tl(next_body)}
            {:error, err} -> {:error, err}
          end
        else
          {:ok, body["rows"]}
        end

      {:error, err} ->
        Logger.error("Fail to get #{principal_url} PRODUCERS\n #{inspect(err)}")
        {:error, nil}
    end
  end

  def calc_votes(principal_node, principal_url, block_num) do
    Logger.info("#{principal_node} >>> Starting Calc Votes & Fork Report Task")

    case get_producers_table(principal_url) do
      {:ok, producers} ->
        # total votes
        total_votes =
          producers
          |> Enum.reduce(0.0, fn r, acc -> String.to_float(r["total_votes"]) + acc end)

        # sort producers
        producers =
          producers
          |> Enum.sort(fn a, b ->
            String.to_float(a["total_votes"]) >= String.to_float(b["total_votes"])
          end)

        # update respective nodes
        producers
        |> Enum.with_index(1)
        |> Enum.each(fn {producer, index} ->
          votes_count = String.to_float(producer["total_votes"])
          vote_percentage = votes_count / total_votes

          Logger.info(
            "Producer #{producer["owner"]} - Votes Count/%: #{votes_count} (#{vote_percentage})"
          )

          GenServer.cast(
            String.to_atom(producer["owner"]),
            {:update_votes, votes_count, vote_percentage, index}
          )
        end)

        # verify sync and forking report
        fork_report(producers, block_num)

      err ->
        # error, rollbacks to active status
        Logger.info(
          "Fail to get Producer Votes Info from #{principal_node}, error:\n#{inspect(err)}"
        )
    end
  end

  def fork_report(producers, block_num) do
    results = collect_producers_stats(producers, block_num)

    # news/inactives nodes
    inactives_report = get_inactives_report(results.inactives)

    # 1/3 network kill rule
    one_third_off_report = get_one_third_network_off_report(results.errors)

    # fork check
    forks_report = get_forks_report(results.actives)

    final_report =
      (inactives_report || "") <> (one_third_off_report || "") <> (forks_report || "")

    if String.length(final_report) > 0 do
      Database.insert_alert(Alerts.nodes_full_fork_report(), final_report)
    end
  end

  def collect_producers_stats(producers, block_num) do
    producers
    |> Enum.take(21)
    |> Enum.map(fn producer ->
      Task.async(__MODULE__, :report_producer, [producer["owner"], block_num])
    end)
    |> Task.yield_many(10_000)
    |> Enum.map(fn {task, res} ->
      res || {:shutdown, Task.shutdown(task, :brutal_kill)}
    end)
    |> Enum.with_index()
    |> Enum.reduce(%{inactives: [], errors: [], actives: []}, fn {res, index}, acc ->
      case res do
        {:ok, {:error_state, _acc, _str}} ->
          %{acc | inactives: [Enum.at(producers, index) | acc.inactives]}

        {:ok, {:ok, account, producer_data}} ->
          %{acc | actives: [{account, producer_data} | acc.actives]}

        _ ->
          %{acc | errors: [Enum.at(producers, index) | acc.errors]}
      end
    end)
  end

  def get_forks_report(actives) do
    with true <- Enum.count(actives) > 0,
         groups <- group_by_block_stats(actives),
         true <- Enum.count(groups) > 1 do
      # if we have more than one group, a fork was detected
      rep = """
      FORK DETECTED
      The following different groups with different block info data
      were detected:
      """

      rep_details =
        groups
        |> Enum.with_index(1)
        |> Enum.map(fn {{accounts, data}, index} ->
          accounts_txt = accounts |> Enum.join("; ")
          "Group #{index}: #{accounts_txt}<br/> Block Data: #{inspect(data)}<br/>-"
        end)
        |> Enum.join("\n")

      rep <>
        rep_details <>
        """

        Please check the above groups and verify if any action is needed.
        """
    else
      _ -> nil
    end
  end

  def get_one_third_network_off_report(errors) do
    errors_count = Enum.count(errors)

    if errors_count >= 7 do
      rep = """
      1/3 NODES OFF - NETWORK KILL
      The following #{errors_count} nodes are OFF, please check the network:
      """

      items =
        errors
        |> Enum.map(fn r -> r["owner"] end)
        |> Enum.join(" - ")

      rep <>
        items <>
        """

        You may need to check the block producers and solve the issue across
        the network.
        """
    end
  end

  def get_inactives_report(inactives) do
    inactives_count = Enum.count(inactives)

    if inactives_count > 0 do
      rep = """
      From the Top 21 Voted Block Producers, Windshield could not find
      external node configuration for the following ones:
      """

      items =
        inactives
        |> Enum.map(fn r -> r["owner"] end)
        |> Enum.join(" - ")

      rep <>
        items <>
        """

        Total: #{Enum.count(inactives_count)}
        Please create and setup addresses for above nodes.
        """
    end
  end

  def group_by_block_stats(nodes) do
    nodes
    |> Enum.reduce([], fn {account, block_data}, acc ->
      groups = Enum.filter(acc, fn {_accounts, data} -> data == block_data end)

      if Enum.count(groups) < 1 do
        [{[account], block_data} | acc]
      else
        acc
        |> Enum.map(fn {accounts, data} ->
          if data == block_data do
            {[account | accounts], data}
          else
            {accounts, data}
          end
        end)
      end
    end)
  end

  def report_producer(account, block_num) do
    with {:ok, state} <- account |> String.to_atom() |> Node.get_state() do
      case state.status do
        :active -> get_block_info(state, block_num)
        status -> {:error_status, account, status}
      end
    else
      _ -> {:error_state, account, "Fail to get #{account} state"}
    end
  end

  def get_block_info(state, block_num, iteration \\ 0) do
    case EosApi.get_block_info(state.url, block_num) do
      {:ok, block_data} ->
        {:ok, state.account,
         %{
           "block_num" => block_num,
           "producer" => block_data["producer"],
           "timestamp" => block_data["timestamp"],
           "previous" => block_data["previous"],
           "transaction_mroot" => block_data["transaction_mroot"],
           "action_mroot" => block_data["action_mroot"],
           "id" => block_data["id"],
           "ref_block_prefix" => block_data["ref_block_prefix"]
         }}

      {:error, failure} ->
        # try 3 times
        if iteration + 1 < 3 do
          get_block_info(state, block_num, iteration + 1)
        else
          Logger.error(
            "#{state["account"]} >>> Fail to get Block info for Fork Report - error:\n #{
              inspect(failure)
            }"
          )

          {:error_block, state["account"], "Fail to get Block info for Fork Report"}
        end
    end
  end
end
