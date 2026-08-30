defmodule Bibtime.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      BibtimeWeb.Telemetry,
      Bibtime.Repo,
      {Ecto.Migrator,
       repos: Application.fetch_env!(:bibtime, :ecto_repos), skip: skip_migrations?()},
      {DNSCluster, query: Application.get_env(:bibtime, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Bibtime.PubSub},
      {Task.Supervisor, name: Bibtime.TaskSupervisor},
      Bibtime.RateLimiter,
      # In dev and test this starts no browser at all (`on_demand`); in
      # production it warms a single Chrome session. Either way the renderer
      # gets a supervisor that outlives the request that triggered it. See
      # config/prod.exs for why the two environments differ.
      {ChromicPDF, Application.get_env(:bibtime, ChromicPDF, [])},
      # Start to serve requests, typically the last entry
      BibtimeWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Bibtime.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    BibtimeWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp skip_migrations?() do
    # By default, sqlite migrations are run when using a release
    System.get_env("RELEASE_NAME") == nil
  end
end
