defmodule Bibtime.Repo do
  use Ecto.Repo,
    otp_app: :bibtime,
    adapter: Ecto.Adapters.SQLite3
end
