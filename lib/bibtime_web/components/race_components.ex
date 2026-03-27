defmodule BibtimeWeb.RaceComponents do
  @moduledoc """
  Shared UI components for race status display and ranking badges.
  """
  use Phoenix.Component
  use Gettext, backend: BibtimeWeb.Gettext

  import BibtimeWeb.LocaleHelpers

  @doc """
  Renders a status pill badge for a race status.

  ## Examples

      <.status_pill status={@race.status} />
      <.status_pill status={@race.status} class="uppercase tracking-wide" />
  """
  attr :status, :atom, required: true
  attr :class, :string, default: nil

  def status_pill(assigns) do
    ~H"""
    <span class={[
      "rounded-full px-2.5 py-0.5 text-xs font-medium",
      status_pill_class(@status),
      @class
    ]}>
      {format_race_status(@status)}
    </span>
    """
  end

  @doc """
  Renders a rank badge for race results.

  ## Examples

      <.rank_badge rank={1} />
      <.rank_badge rank={1} size={:lg} />
  """
  attr :rank, :integer, required: true
  attr :size, :atom, default: :sm, values: [:sm, :lg]

  def rank_badge(assigns) do
    ~H"""
    <span class={rank_class(@rank, @size)}>
      {@rank}
    </span>
    """
  end

  defp status_pill_class(status) do
    case status do
      :draft -> "bg-base-content/10 text-base-content/60"
      :registration_open -> "bg-info/15 text-info"
      :registration_closed -> "bg-warning/15 text-warning"
      :in_progress -> "bg-success/15 text-success"
      :finished -> "bg-accent/15 text-accent"
      :archived -> "bg-neutral/15 text-neutral"
      _ -> "bg-base-content/10 text-base-content/60"
    end
  end

  defp rank_class(rank, :sm) do
    case rank do
      1 ->
        "inline-flex items-center justify-center w-7 h-7 rounded-full bg-warning/20 text-warning font-bold text-sm font-mono"

      2 ->
        "inline-flex items-center justify-center w-7 h-7 rounded-full bg-base-300/60 text-base-content/70 font-bold text-sm font-mono"

      3 ->
        "inline-flex items-center justify-center w-7 h-7 rounded-full bg-secondary/15 text-secondary font-bold text-sm font-mono"

      _ ->
        "font-mono text-sm text-base-content/60"
    end
  end

  defp rank_class(rank, :lg) do
    case rank do
      1 ->
        "inline-flex items-center justify-center w-10 h-10 rounded-full bg-warning/25 text-warning font-bold text-xl font-mono"

      2 ->
        "inline-flex items-center justify-center w-10 h-10 rounded-full bg-base-300/60 text-base-content/70 font-bold text-xl font-mono"

      3 ->
        "inline-flex items-center justify-center w-10 h-10 rounded-full bg-secondary/20 text-secondary font-bold text-xl font-mono"

      _ ->
        "font-mono text-xl text-base-content/60"
    end
  end
end
