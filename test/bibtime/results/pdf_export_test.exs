defmodule Bibtime.Results.PdfExportTest do
  @moduledoc """
  Guards the ChromicPDF wiring rather than the rendering itself: CI has no
  Chrome, and the bug this covers was that the supervisor never ran at all.
  """
  use Bibtime.DataCase

  describe "ChromicPDF supervision" do
    test "the supervisor is running, so a render never has to start one" do
      # Registered under the ChromicPDF module itself, not ChromicPDF.Supervisor
      # — the old lazy starter checked the latter, a name that never exists, so
      # it re-started the supervisor on every single request.
      assert is_pid(Process.whereis(ChromicPDF))
    end

    test "the test env runs on_demand, so booting the suite starts no browser" do
      # Production deliberately differs — see config/prod.exs.
      assert Application.get_env(:bibtime, ChromicPDF)[:on_demand] == true

      children = Supervisor.which_children(ChromicPDF)
      refute Enum.any?(children, fn {id, _, _, _} -> id == ChromicPDF.Browser end)
    end
  end
end
