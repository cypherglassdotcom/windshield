defmodule Windshield.EosApi do
  @moduledoc """
  Apis to access nodes via EOSRPC
  """

  use Tesla

  plug(Tesla.Middleware.JSON)

  plug(Tesla.Middleware.Timeout, timeout: 3_000)

  def get_chain_info(url) do
    url
    |> Kernel.<>("/v1/chain/get_info")
    |> get(opts: [adapter: [timeout: 1_000]])
    |> validate_request()
  end

  def check_bp_pause(url) do
    url
    |> Kernel.<>("/v1/producer/paused")
    |> get(opts: [adapter: [timeout: 1_000]])
    |> validate_request()
  end

  def get_block_info(url, block_num) do
    url
    |> Kernel.<>("/v1/chain/get_block")
    |> post(%{block_num_or_id: block_num})
    |> validate_request()
  end

  def get_producers(url) do
    data = %{
      "scope" => "eosio",
      "code" => "eosio",
      "table" => "producers",
      "json" => "true",
      "limit" => 9999
    }

    url
    |> Kernel.<>("/v1/chain/get_table_rows")
    |> post(data)
    |> validate_request()
  end

  def validate_request(response) do
    with {:ok, res} <- response,
         %{status: status, body: body} <- res,
         true <- status in [200, 201, 203, 204] do
      {:ok, body}
    else
      _ -> {:error, response}
    end
  end
end
