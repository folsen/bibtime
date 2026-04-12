defmodule BibtimeStation do
  @moduledoc """
  Top-level application module for the BibTime timing station firmware.

  The actual work lives in:

    * `BibtimeStation.Reader` — owns the R200 serial port
    * `BibtimeStation.ReadPipeline` — dedup + counting
    * `BibtimeStation.Uplink` — HTTP client to the BibTime server
    * `BibtimeStation.Buffer` — offline read buffer
    * `BibtimeStation.Heartbeat` — periodic status ping
  """
end
