defmodule BibtimeStation.Application do
  @moduledoc """
  Top-level supervisor for the BibTime timing station.

  Uses `:rest_for_one` so that:

  * a `Reader` crash restarts the entire downstream pipeline
    (`ReadPipeline`, `Uplink`, `Heartbeat`)
  * a `Buffer` crash restarts everything (Reader and below)
  * a `Heartbeat` crash affects nothing else

  In `:test` and `:dev` we don't auto-start the supervised processes
  by default — tests and dev IEx sessions opt in via the
  `:start_supervision_tree` config flag (set to `true` only in
  `prod.exs`). This keeps `iex -S mix` from grabbing the serial port
  and prevents tests from fighting over the buffer ETS table.
  """

  use Application

  @impl true
  def start(_type, _args) do
    children =
      if start_supervision_tree?() do
        [
          BibtimeStation.Buffer,
          BibtimeStation.Reader,
          BibtimeStation.ReadPipeline,
          BibtimeStation.Uplink,
          BibtimeStation.Heartbeat
        ]
      else
        []
      end

    opts = [strategy: :rest_for_one, name: BibtimeStation.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp start_supervision_tree? do
    Application.get_env(:bibtime_station, :start_supervision_tree, false)
  end
end
