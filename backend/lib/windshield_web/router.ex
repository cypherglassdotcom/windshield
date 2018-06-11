defmodule WindshieldWeb.Router do
  use WindshieldWeb, :router

  pipeline :api do
    plug(:accepts, ["json"])
  end

  pipeline :browser do
    plug(:accepts, ["html"])
  end

  if Mix.env() == :dev do
    #    pipe_through([:browser])
    forward("/mailbox", Bamboo.EmailPreviewPlug)
  end

  scope "/api", WindshieldWeb do
    pipe_through(:api)

    get("/health-check", RootController, :health_check)
    get("/version", RootController, :version)
    post("/auth", RootController, :auth)
    get("/monitor-state", RootController, :monitor_state)
    get("/node-state/:account", RootController, :node_state)

    if Mix.env() == :dev do
      get("/test-email", RootController, :test_email)
      get("/test-slack", RootController, :test_slack)
    end
  end
end
