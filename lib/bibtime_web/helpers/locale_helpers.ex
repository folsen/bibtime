defmodule BibtimeWeb.LocaleHelpers do
  @moduledoc """
  Locale-aware formatting helpers for dates, times, and status labels.
  """

  use Gettext, backend: BibtimeWeb.Gettext

  @swedish_months %{
    1 => "januari",
    2 => "februari",
    3 => "mars",
    4 => "april",
    5 => "maj",
    6 => "juni",
    7 => "juli",
    8 => "augusti",
    9 => "september",
    10 => "oktober",
    11 => "november",
    12 => "december"
  }

  @swedish_months_short %{
    1 => "jan",
    2 => "feb",
    3 => "mar",
    4 => "apr",
    5 => "maj",
    6 => "jun",
    7 => "jul",
    8 => "aug",
    9 => "sep",
    10 => "okt",
    11 => "nov",
    12 => "dec"
  }

  @doc """
  Formats a date in a long locale-aware format.
  English: "March 20, 2026"
  Swedish: "20 mars 2026"
  """
  def format_date(%Date{} = date) do
    locale = Gettext.get_locale(BibtimeWeb.Gettext)
    format_date(date, locale)
  end

  def format_date(nil), do: ""

  def format_date(%Date{} = date, "sv") do
    "#{date.day} #{@swedish_months[date.month]} #{date.year}"
  end

  def format_date(%Date{} = date, _locale) do
    Calendar.strftime(date, "%B %d, %Y")
  end

  @doc """
  Formats a date in a short locale-aware format.
  English: "Mar 20, 2026"
  Swedish: "20 mar 2026"
  """
  def format_date_short(%Date{} = date) do
    locale = Gettext.get_locale(BibtimeWeb.Gettext)
    format_date_short(date, locale)
  end

  def format_date_short(%DateTime{} = dt) do
    format_date_short(DateTime.to_date(dt))
  end

  def format_date_short(%NaiveDateTime{} = ndt) do
    format_date_short(NaiveDateTime.to_date(ndt))
  end

  def format_date_short(nil), do: ""

  def format_date_short(%Date{} = date, "sv") do
    "#{date.day} #{@swedish_months_short[date.month]} #{date.year}"
  end

  def format_date_short(%Date{} = date, _locale) do
    Calendar.strftime(date, "%b %d, %Y")
  end

  @doc """
  Translates a race status atom to a display string.
  """
  def format_race_status(:draft), do: gettext("Draft")
  def format_race_status(:registration_open), do: gettext("Registration Open")
  def format_race_status(:registration_closed), do: gettext("Registration Closed")
  def format_race_status(:in_progress), do: gettext("In Progress")
  def format_race_status(:finished), do: gettext("Finished")
  def format_race_status(:archived), do: gettext("Archived")

  def format_race_status(status) do
    status
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.split(" ")
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  @doc """
  Translates a participant status atom to a display string.
  """
  def format_participant_status(:registered), do: gettext("Registered")
  def format_participant_status(:racing), do: gettext("Racing")
  def format_participant_status(:dns), do: "DNS"
  def format_participant_status(:dnf), do: "DNF"
  def format_participant_status(:dsq), do: "DSQ"
  def format_participant_status(:finished), do: gettext("Finished")

  def format_participant_status(status) do
    status |> Atom.to_string() |> String.capitalize()
  end

  @doc """
  Translates a participant status to uppercase for admin displays.
  """
  def format_participant_status_upper(:dns), do: "DNS"
  def format_participant_status_upper(:dnf), do: "DNF"
  def format_participant_status_upper(:dsq), do: "DSQ"

  def format_participant_status_upper(status) do
    status |> Atom.to_string() |> String.upcase()
  end

  @doc """
  Returns translated race type options for select inputs.
  """
  def race_type_options do
    [
      {gettext("Triathlon"), :triathlon},
      {gettext("Running"), :running},
      {gettext("Cycling"), :cycling},
      {gettext("Swimming"), :swimming},
      {gettext("Custom"), :custom}
    ]
  end

  @doc """
  Returns translated status options for select inputs.
  """
  def status_options do
    [
      {gettext("Draft"), :draft},
      {gettext("Registration Open"), :registration_open},
      {gettext("Registration Closed"), :registration_closed},
      {gettext("In Progress"), :in_progress},
      {gettext("Finished"), :finished},
      {gettext("Archived"), :archived}
    ]
  end

  @doc """
  Returns translated gender options for select inputs.
  """
  def gender_options do
    [
      {gettext("Male"), :male},
      {gettext("Female"), :female},
      {gettext("Other"), :other}
    ]
  end

  @doc """
  Translates a user role string to a display string.
  """
  def format_user_role("admin"), do: gettext("Admin")
  def format_user_role("timer"), do: gettext("Timer")
  def format_user_role("user"), do: gettext("User")
  def format_user_role(role), do: String.capitalize(to_string(role))

  @doc """
  Returns locale display name.
  """
  def locale_name("en"), do: "English"
  def locale_name("sv"), do: "Svenska"
  def locale_name(locale), do: locale
end
