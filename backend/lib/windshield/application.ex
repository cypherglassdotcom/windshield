defmodule Windshield.Application do
  @moduledoc """
  WINDSHIELD: keep track of EOS Nodes and receive alerts if anything goes wrong
  """

  use Application

  def start(_type, _args) do
    import Supervisor.Spec

    # Define workers and child supervisors to be supervised
    children = [
      supervisor(WindshieldWeb.Endpoint, []),
      worker(Mongo, [Application.get_env(:mongodb, Mongo)]),
      worker(Windshield.PrincipalMonitor, [[name: :principal_monitor]])
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Windshield.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  def config_change(changed, _new, removed) do
    WindshieldWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
