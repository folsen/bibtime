defmodule BibtimeWeb.Router do
  use BibtimeWeb, :router

  import BibtimeWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {BibtimeWeb.Layouts, :root}
    plug :protect_from_forgery

    plug :put_secure_browser_headers, %{
      "content-security-policy" =>
        "default-src 'self'; " <>
          "script-src 'self'; " <>
          "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; " <>
          "font-src 'self' https://fonts.gstatic.com; " <>
          "img-src 'self' data: blob:; " <>
          "connect-src 'self' ws: wss:; " <>
          "frame-ancestors 'none'; " <>
          "base-uri 'self'; " <>
          "form-action 'self'"
    }

    plug :fetch_current_scope_for_user
    plug BibtimeWeb.Plugs.SetLocale
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Public routes (no auth required)
  scope "/", BibtimeWeb do
    pipe_through :browser

    get "/", PageController, :home

    live_session :public,
      on_mount: [{BibtimeWeb.UserAuth, :assign_current_scope}] do
      live "/races/:slug", Public.RaceLive.Show, :show
      live "/races/:slug/results", Public.ResultsLive.Index, :index
      live "/races/:slug/photos", Public.PhotoLive.Index, :index
      live "/races/:slug/register", Public.RegistrationLive.New, :new

      live "/races/:slug/register/confirmation/:participant_id",
           Public.RegistrationLive.Show,
           :show

      live "/races/:slug/my-registration/:token", Public.RegistrationLive.MyRegistration, :show
    end

    get "/races/:slug/results/export/csv", ExportController, :results_csv
  end

  # Kiosk mode (fullscreen, no nav — for projectors/TVs at race venues)
  scope "/", BibtimeWeb do
    pipe_through :browser

    live_session :kiosk,
      on_mount: [{BibtimeWeb.UserAuth, :assign_current_scope}],
      layout: {BibtimeWeb.Layouts, :kiosk},
      root_layout: {BibtimeWeb.Layouts, :kiosk_root} do
      live "/races/:slug/kiosk", Public.KioskLive.Index, :index
    end
  end

  # Admin routes (require admin user)
  scope "/", BibtimeWeb do
    pipe_through [:browser, :require_authenticated_user, :require_admin_user]

    live_session :admin,
      on_mount: [{BibtimeWeb.UserAuth, :require_authenticated_user}],
      layout: {BibtimeWeb.Layouts, :admin} do
      live "/admin/races", Admin.RaceLive.Index, :index
      live "/admin/races/new", Admin.RaceLive.New, :new
      live "/admin/races/:id", Admin.RaceLive.Show, :show
      live "/admin/races/:id/edit", Admin.RaceLive.Edit, :edit
      live "/admin/races/:id/participants", Admin.ParticipantLive.Index, :index
      live "/admin/races/:id/participants/new", Admin.ParticipantLive.New, :new
      live "/admin/races/:id/participants/:participant_id/edit", Admin.ParticipantLive.Edit, :edit
      live "/admin/races/:id/photos", Admin.PhotoLive.Index, :index
      live "/admin/races/:id/payments", Admin.PaymentLive.Index, :index
      live "/admin/users", Admin.UserLive.Index, :index
    end
  end

  # Timer routes (require timer or admin user)
  scope "/", BibtimeWeb do
    pipe_through [:browser, :require_authenticated_user, :require_timer_or_admin_user]

    live_session :timer,
      on_mount: [{BibtimeWeb.UserAuth, :require_authenticated_user}],
      layout: {BibtimeWeb.Layouts, :admin} do
      live "/admin/races/:id/timing", Admin.TimingLive.Index, :index
    end
  end

  # Health check endpoint for load balancers (no auth, no CSRF)
  scope "/", BibtimeWeb do
    pipe_through :api

    get "/healthz", HealthController, :index
  end

  # Stripe webhook endpoint (no auth, no CSRF — signature verified in controller)
  scope "/webhooks", BibtimeWeb do
    pipe_through :api

    post "/stripe", StripeWebhookController, :create
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:bibtime, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: BibtimeWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  # Authenticated participant routes (any logged-in user)
  scope "/", BibtimeWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :authenticated,
      on_mount: [{BibtimeWeb.UserAuth, :require_authenticated_user}] do
      live "/profile", Public.ProfileLive.Index, :index
      live "/profile/races/:participant_id", Public.ProfileLive.Show, :show
      live "/my-races", Public.MyRacesLive.Index, :index
      live "/my-races/:participant_id/edit", Public.MyRacesLive.Edit, :edit
    end

    get "/users/settings", UserSettingsController, :edit
    put "/users/settings", UserSettingsController, :update
    get "/users/settings/confirm-email/:token", UserSettingsController, :confirm_email
  end

  scope "/", BibtimeWeb do
    pipe_through [:browser]

    get "/users/log-in", UserSessionController, :new
    get "/users/log-in/:token", UserSessionController, :confirm
    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
    put "/locale", LocaleController, :update
  end
end
