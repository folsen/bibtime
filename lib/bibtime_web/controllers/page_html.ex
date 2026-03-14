defmodule BibtimeWeb.PageHTML do
  @moduledoc """
  This module contains pages rendered by PageController.

  See the `page_html` directory for all templates available.
  """
  use BibtimeWeb, :html

  embed_templates "page_html/*"

  defp race_status_style(status) do
    case status do
      :draft -> "bg-base-300/60 text-base-content/50"
      :registration_open -> "bg-info/15 text-info"
      :registration_closed -> "bg-warning/15 text-warning"
      :in_progress -> "bg-success/15 text-success"
      :finished -> "bg-accent/15 text-accent"
      :archived -> "bg-neutral/15 text-neutral"
      _ -> "bg-base-300/60 text-base-content/50"
    end
  end
end
