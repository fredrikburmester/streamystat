defmodule StreamystatServerWeb.Router do
  use StreamystatServerWeb, :router

  pipeline :api do
    plug(:accepts, ["json"])
  end

  scope "/api", StreamystatServerWeb do
    pipe_through(:api)

    resources "/servers", ServerController, only: [:index, :create] do
      post("/sync", SyncController, :partial_sync)
      post("/sync/full", SyncController, :full_sync)
      post("/sync/users", SyncController, :sync_users)
      post("/sync/libraries", SyncController, :sync_libraries)
      post("/sync/items", SyncController, :sync_items)
      post("/sync/playback-statistics", SyncController, :sync_playback_stats)
      get("/statistics", StatisticsController, :index)
      get("/statistics/history", StatisticsController, :history)
      resources("/users", UserController, only: [:index, :show])
    end

    get("/health", HealthController, :check)
  end

  use Phoenix.Router, error_view: StreamystatServerWeb.ErrorJSON

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:streamystat_server, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through([:fetch_session, :protect_from_forgery])

      live_dashboard("/dashboard", metrics: StreamystatServerWeb.Telemetry)
      forward("/mailbox", Plug.Swoosh.MailboxPreview)
    end
  end
end