defmodule Windshield.Database do
  @moduledoc """
  Database service interface, read and persist data to mongo
  """

  require Logger

  @coll_opts [limit: 9_999, pool: DBConnection.Poolboy]
  @collection_settings "settings"
  @collection_stats "stats"
  @collection_nodes "nodes"
  @collection_producers "producers"
  @collection_alerts "alerts"

  ################################################################
  # Nodes
  ################################################################

  def get_nodes do
    data =
      :windshield
      |> Mongo.find(@collection_nodes, %{}, @coll_opts)
      |> Enum.to_list()

    {:ok, data}
  end

  def get_node(account) do
    res =
      :windshield
      |> Mongo.find_one(@collection_nodes, %{account: account}, @coll_opts)

    {:ok, res}
  end

  def upsert_node(account, ip, port, is_ssl, is_watchable, type) do
    new_node = %{
      "account" => account,
      "ip" => ip,
      "port" => port,
      "is_ssl" => is_ssl,
      "is_watchable" => is_watchable,
      "type" => type
    }

    res =
      :windshield
      |> Mongo.find_one_and_update(
        @collection_nodes,
        %{"account" => account},
        %{"$set" => new_node},
        [upsert: true] ++ @coll_opts
      )

    case res do
      {:ok, _res} -> {:ok, new_node}
      _ -> {:error, "Fail to create/update node #{inspect(new_node)}"}
    end
  end

  ################################################################
  # Producers
  ################################################################

  def get_producers do
    data =
      :windshield
      |> Mongo.find(@collection_producers, %{}, @coll_opts)
      |> Enum.to_list()

    {:ok, data}
  end

  def update_producer(producer) do
    :windshield
    |> Mongo.find_one_and_update(
      @collection_producers,
      %{"account" => producer["account"]},
      %{"$set" => producer},
      [upsert: true] ++ @coll_opts
    )
  end

  ################################################################
  # Alerts
  ################################################################

  def get_alerts do
    data =
      :windshield
      |> Mongo.find(@collection_alerts, %{}, [sort: [created_at: -1]] ++ @coll_opts)
      |> Enum.to_list()

    {:ok, data}
  end

  def check_alert(id) do
    :windshield
    |> Mongo.update_one(
      @collection_alerts,
      %{_id: id},
      %{"$set" => %{"checked" => true}},
      @coll_opts
    )
  end

  def insert_alert(type, description, data \\ nil) do
    new_alert = %{
      type: type,
      description: description,
      data: data,
      created_at: System.os_time(),
      checked: false
    }

    res =
      :windshield
      |> Mongo.insert_one(@collection_alerts, new_alert, @coll_opts)

    Logger.info("Broadcasting new Alert >>> #{inspect(new_alert)}")
    WindshieldWeb.Endpoint.broadcast("monitor:main", "emit_alert", new_alert)
    Windshield.Alerts.alert_mail(type, description)
    Windshield.Alerts.alert_slack(type, description)

    res
  end

  ################################################################
  # Stats
  ################################################################

  def create_stats(stats) do
    :windshield
    |> Mongo.insert_one(@collection_stats, stats, @coll_opts)
  end

  def update_stats(stats) do
    :windshield
    |> Mongo.update_one(@collection_stats, %{id: 1}, %{"$set" => stats}, @coll_opts)
  end

  def get_stats do
    stats =
      :windshield
      |> Mongo.find_one(@collection_stats, %{id: 1}, @coll_opts)

    if stats do
      {:ok, stats}
    else
      new_stats = %{"id" => 1, "last_block" => 0}
      create_stats(new_stats)
      {:ok, new_stats}
    end
  end

  ################################################################
  # Settings
  ################################################################

  def create_settings(settings) do
    :windshield
    |> Mongo.insert_one(@collection_settings, settings, @coll_opts)
  end

  def get_settings do
    settings =
      :windshield
      |> Mongo.find_one(@collection_settings, %{id: 1}, @coll_opts)

    if settings != nil do
      {:ok, settings}
    else
      new_settings = %{
        "id" => 1,
        "principal_node" => "",
        "monitor_loop_interval" => 500,
        "node_loop_interval" => 500,
        "same_alert_interval_mins" => 10,
        "bp_tolerance_time_secs" => 180,
        "unsynched_blocks_to_alert" => 20,
        "failed_pings_to_alert" => 20,
        "calc_votes_interval_secs" => 300
      }

      create_settings(new_settings)
      new_settings
    end
  end

  def update_settings(settings) do
    :windshield
    |> Mongo.update_one(@collection_settings, %{id: 1}, %{"$set" => settings}, @coll_opts)
  end
end
