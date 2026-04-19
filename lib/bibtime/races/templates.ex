defmodule Bibtime.Races.Templates do
  @moduledoc """
  Built-in race templates with predefined splits and gender auto-categories.
  """

  @gender_auto_categories [
    %{type: :gender, name: "Men", gender_value: :male, sort_order: 1},
    %{type: :gender, name: "Women", gender_value: :female, sort_order: 2}
  ]

  def list do
    [
      %{
        id: "olympic_triathlon",
        name: "Olympic Triathlon",
        race_type: :triathlon,
        description: "Standard Olympic distance triathlon: 1.5km swim, 40km bike, 10km run.",
        splits: [
          %{
            name: "Swim",
            short_name: "SWIM",
            leg_type: :swim,
            distance_meters: 1500,
            sort_order: 1
          },
          %{
            name: "T1",
            short_name: "T1",
            leg_type: :transition,
            distance_meters: nil,
            sort_order: 2
          },
          %{
            name: "Bike",
            short_name: "BIKE",
            leg_type: :bike,
            distance_meters: 40_000,
            sort_order: 3
          },
          %{
            name: "T2",
            short_name: "T2",
            leg_type: :transition,
            distance_meters: nil,
            sort_order: 4
          },
          %{
            name: "Run",
            short_name: "RUN",
            leg_type: :run,
            distance_meters: 10_000,
            sort_order: 5
          }
        ],
        auto_categories: @gender_auto_categories
      },
      %{
        id: "sprint_triathlon",
        name: "Sprint Triathlon",
        race_type: :triathlon,
        description: "Sprint distance triathlon: 750m swim, 20km bike, 5km run.",
        splits: [
          %{
            name: "Swim",
            short_name: "SWIM",
            leg_type: :swim,
            distance_meters: 750,
            sort_order: 1
          },
          %{
            name: "T1",
            short_name: "T1",
            leg_type: :transition,
            distance_meters: nil,
            sort_order: 2
          },
          %{
            name: "Bike",
            short_name: "BIKE",
            leg_type: :bike,
            distance_meters: 20_000,
            sort_order: 3
          },
          %{
            name: "T2",
            short_name: "T2",
            leg_type: :transition,
            distance_meters: nil,
            sort_order: 4
          },
          %{name: "Run", short_name: "RUN", leg_type: :run, distance_meters: 5_000, sort_order: 5}
        ],
        auto_categories: @gender_auto_categories
      },
      %{
        id: "duathlon",
        name: "Duathlon",
        race_type: :custom,
        description: "Standard duathlon: 10km run, 40km bike, 5km run.",
        splits: [
          %{
            name: "Run 1",
            short_name: "RUN1",
            leg_type: :run,
            distance_meters: 10_000,
            sort_order: 1
          },
          %{
            name: "T1",
            short_name: "T1",
            leg_type: :transition,
            distance_meters: nil,
            sort_order: 2
          },
          %{
            name: "Bike",
            short_name: "BIKE",
            leg_type: :bike,
            distance_meters: 40_000,
            sort_order: 3
          },
          %{
            name: "T2",
            short_name: "T2",
            leg_type: :transition,
            distance_meters: nil,
            sort_order: 4
          },
          %{
            name: "Run 2",
            short_name: "RUN2",
            leg_type: :run,
            distance_meters: 5_000,
            sort_order: 5
          }
        ],
        auto_categories: @gender_auto_categories
      },
      %{
        id: "aquathlon",
        name: "Aquathlon",
        race_type: :custom,
        description: "Aquathlon: 1km swim, 5km run.",
        splits: [
          %{
            name: "Swim",
            short_name: "SWIM",
            leg_type: :swim,
            distance_meters: 1_000,
            sort_order: 1
          },
          %{
            name: "T1",
            short_name: "T1",
            leg_type: :transition,
            distance_meters: nil,
            sort_order: 2
          },
          %{name: "Run", short_name: "RUN", leg_type: :run, distance_meters: 5_000, sort_order: 3}
        ],
        auto_categories: @gender_auto_categories
      },
      %{
        id: "5k",
        name: "5K Run",
        race_type: :running,
        description: "Standard 5 kilometer road race.",
        splits: [
          %{
            name: "Finish",
            short_name: "FIN",
            leg_type: :run,
            distance_meters: 5_000,
            sort_order: 1
          }
        ],
        auto_categories: @gender_auto_categories
      },
      %{
        id: "10k",
        name: "10K Run",
        race_type: :running,
        description: "Standard 10 kilometer road race.",
        splits: [
          %{name: "5K", short_name: "5K", leg_type: :run, distance_meters: 5_000, sort_order: 1},
          %{
            name: "Finish",
            short_name: "FIN",
            leg_type: :run,
            distance_meters: 10_000,
            sort_order: 2
          }
        ],
        auto_categories: @gender_auto_categories
      },
      %{
        id: "half_marathon",
        name: "Half Marathon",
        race_type: :running,
        description: "Half marathon: 21.1 km.",
        splits: [
          %{name: "5K", short_name: "5K", leg_type: :run, distance_meters: 5_000, sort_order: 1},
          %{
            name: "10K",
            short_name: "10K",
            leg_type: :run,
            distance_meters: 10_000,
            sort_order: 2
          },
          %{
            name: "15K",
            short_name: "15K",
            leg_type: :run,
            distance_meters: 15_000,
            sort_order: 3
          },
          %{
            name: "Finish",
            short_name: "FIN",
            leg_type: :run,
            distance_meters: 21_097,
            sort_order: 4
          }
        ],
        auto_categories: @gender_auto_categories
      },
      %{
        id: "marathon",
        name: "Marathon",
        race_type: :running,
        description: "Full marathon: 42.195 km.",
        splits: [
          %{name: "5K", short_name: "5K", leg_type: :run, distance_meters: 5_000, sort_order: 1},
          %{
            name: "10K",
            short_name: "10K",
            leg_type: :run,
            distance_meters: 10_000,
            sort_order: 2
          },
          %{
            name: "Half",
            short_name: "HALF",
            leg_type: :run,
            distance_meters: 21_097,
            sort_order: 3
          },
          %{
            name: "30K",
            short_name: "30K",
            leg_type: :run,
            distance_meters: 30_000,
            sort_order: 4
          },
          %{
            name: "Finish",
            short_name: "FIN",
            leg_type: :run,
            distance_meters: 42_195,
            sort_order: 5
          }
        ],
        auto_categories: @gender_auto_categories
      }
    ]
  end

  def get(template_id) do
    Enum.find(list(), &(&1.id == template_id))
  end

  def options_for_select do
    [{"No template (blank race)", ""}] ++
      Enum.map(list(), fn t -> {t.name, t.id} end)
  end
end
