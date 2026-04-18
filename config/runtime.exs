import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# Load .env file in dev/test for convenience (Stripe keys, etc.)
if config_env() in [:dev, :test] do
  env_file = Path.expand("../.env", __DIR__)

  if File.exists?(env_file) do
    env_file
    |> File.read!()
    |> String.split("\n")
    |> Enum.each(fn line ->
      line = String.trim(line)

      case line do
        "#" <> _ ->
          :skip

        "" ->
          :skip

        _ ->
          case String.split(line, "=", parts: 2) do
            [key, value] ->
              key = String.trim(key)
              value = value |> String.trim() |> String.trim("\"") |> String.trim("'")

              unless System.get_env(key) do
                System.put_env(key, value)
              end

            _ ->
              :skip
          end
      end
    end)
  end
end

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/bibtime start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :bibtime, BibtimeWeb.Endpoint, server: true
end

config :bibtime, BibtimeWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

# Photo storage: S3-compatible (optional, defaults to local disk).
# Supports AWS S3 and Tigris (via Fly). When `fly storage create` provisions
# a Tigris bucket it injects BUCKET_NAME and AWS_ENDPOINT_URL_S3; both are
# read here automatically.
if System.get_env("PHOTO_STORAGE") == "s3" do
  bucket =
    System.get_env("S3_BUCKET") ||
      System.get_env("BUCKET_NAME") ||
      raise("S3_BUCKET or BUCKET_NAME required when PHOTO_STORAGE=s3")

  config :bibtime, Bibtime.Photos.Storage,
    backend: :s3,
    bucket: bucket

  config :ex_aws,
    access_key_id: System.get_env("AWS_ACCESS_KEY_ID"),
    secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY"),
    region: System.get_env("AWS_REGION", "us-east-1")

  endpoint_url = System.get_env("AWS_ENDPOINT_URL_S3") || System.get_env("S3_ENDPOINT_URL")
  s3_host = System.get_env("S3_HOST")

  cond do
    endpoint_url ->
      uri = URI.parse(endpoint_url)

      config :ex_aws, :s3,
        scheme: "#{uri.scheme}://",
        host: uri.host,
        port: uri.port || if(uri.scheme == "https", do: 443, else: 80)

    s3_host ->
      config :ex_aws, :s3,
        scheme: System.get_env("S3_SCHEME", "https://"),
        host: s3_host,
        port: String.to_integer(System.get_env("S3_PORT", "443"))

    true ->
      :ok
  end
end

# Stripe configuration (all environments)
if stripe_key = System.get_env("STRIPE_SECRET_KEY") do
  config :stripity_stripe, api_key: stripe_key
end

if stripe_webhook_secret = System.get_env("STRIPE_WEBHOOK_SECRET") do
  config :stripity_stripe, signing_secret: stripe_webhook_secret
end

if config_env() in [:prod, :staging] do
  database_path =
    System.get_env("DATABASE_PATH") ||
      raise """
      environment variable DATABASE_PATH is missing.
      For example: /etc/bibtime/bibtime.db
      """

  config :bibtime, Bibtime.Repo,
    database: database_path,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "5"),
    journal_mode: :wal,
    cache_size: -64000,
    temp_store: :memory,
    synchronous: :normal

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host =
    System.get_env("PHX_HOST") ||
      raise """
      environment variable PHX_HOST is missing.
      This is the public hostname used for URLs in emails and meta tags.
      Example: bibtime.example.com
      On Fly.io: fly secrets set PHX_HOST=your.domain.com
      """

  config :bibtime, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  # Outbound email sender. Must be on a domain verified with your mail
  # provider (e.g. Resend). Defaults point at a placeholder so misconfigured
  # deploys fail loudly in the provider's UI rather than silently.
  config :bibtime,
    mailer_from_address: System.get_env("MAILER_FROM_ADDRESS", "no-reply@example.com")

  # Resend mailer (opt-in via env var). When unset, the app falls back to
  # the Swoosh.Adapters.Local adapter configured in config.exs. Staging builds
  # (MIX_ENV=staging) keep the local adapter so mail is viewable at
  # /dev/mailbox instead of being delivered to real inboxes.
  if config_env() == :staging do
    config :bibtime, :dev_tools_basic_auth,
      username:
        System.get_env("DEV_TOOLS_BASIC_AUTH_USERNAME") ||
          raise("""
          environment variable DEV_TOOLS_BASIC_AUTH_USERNAME is missing.
          Staging exposes /dev/mailbox and /dev/dashboard behind basic auth.
          Set a username/password via `fly secrets set`.
          """),
      password:
        System.get_env("DEV_TOOLS_BASIC_AUTH_PASSWORD") ||
          raise("environment variable DEV_TOOLS_BASIC_AUTH_PASSWORD is missing.")
  end

  if resend_api_key = System.get_env("RESEND_API_KEY") do
    config :bibtime, Bibtime.Mailer,
      adapter: Swoosh.Adapters.Resend,
      api_key: resend_api_key
  end

  config :bibtime, BibtimeWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :bibtime, BibtimeWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :bibtime, BibtimeWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Here is an example configuration for Mailgun:
  #
  #     config :bibtime, Bibtime.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # Most non-SMTP adapters require an API client. Swoosh supports Req, Hackney,
  # and Finch out-of-the-box. This configuration is typically done at
  # compile-time in your config/prod.exs:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Req
  #
  # See https://hexdocs.pm/swoosh/Swoosh.html#module-installation for details.
end
