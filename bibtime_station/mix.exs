defmodule BibtimeStation.MixProject do
  use Mix.Project

  @app :bibtime_station
  @version "0.1.0"

  def project do
    [
      app: @app,
      version: @version,
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: releases(),
      default_release: @app
    ]
  end

  def application do
    [
      extra_applications: [:logger, :runtime_tools],
      mod: {BibtimeStation.Application, []}
    ]
  end

  defp deps do
    [
      # Serial communication with the R200 RFID reader
      {:circuits_uart, "~> 1.5"},

      # HTTP client for posting reads / heartbeats to the BibTime server
      {:req, "~> 0.5"},

      # JSON encoding/decoding
      {:jason, "~> 1.4"}
    ]
  end

  defp releases do
    [
      {@app,
       [
         # Run as a daemon under systemd, no console attached
         steps: [:assemble, :tar],
         strip_beams: Mix.env() == :prod,
         include_executables_for: [:unix]
       ]}
    ]
  end
end
