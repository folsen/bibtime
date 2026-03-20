# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# This script is designed to run on a fresh database.
# Running it on an already-seeded database will fail due to unique constraints.

alias Bibtime.Repo
alias Bibtime.Accounts
alias Bibtime.Accounts.User
alias Bibtime.Races.{Race, RaceCategory, Split}
alias Bibtime.Participants.Participant
alias Bibtime.Timing.{RaceStart, SplitTime}

# ---------------------------------------------------------------------------
# 1. Admin user
# ---------------------------------------------------------------------------
admin =
  case Accounts.register_user(%{email: "admin@bibtime.local"}) do
    {:ok, user} -> user
    {:error, _} -> Repo.get_by!(User, email: "admin@bibtime.local")
  end

# Set a password on the admin user and grant admin role
admin
|> User.password_changeset(%{password: "password1234"})
|> Ecto.Changeset.put_change(:confirmed_at, DateTime.utc_now(:second))
|> Ecto.Changeset.put_change(:is_admin, true)
|> Repo.update!()

IO.puts("Created admin user: admin@bibtime.local")

if Repo.aggregate(Race, :count) > 0 do
  IO.puts("Race data already exists, skipping seeds.")
  System.halt(0)
end

# ---------------------------------------------------------------------------
# 2. Sample triathlon race
# ---------------------------------------------------------------------------
now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

race =
  Repo.insert!(%Race{
    name: "Stadsparken Triathlon 2026",
    slug: "stadsparken-triathlon-2026",
    description: "Annual sprint triathlon in Stadsparken, Lund",
    date: ~D[2026-06-15],
    location: "Stadsparken, Lund",
    race_type: :triathlon,
    status: :in_progress,
    inserted_at: now,
    updated_at: now
  })

IO.puts("Created race: #{race.name}")

# ---------------------------------------------------------------------------
# 3. Race categories
# ---------------------------------------------------------------------------
cat_elite_men =
  Repo.insert!(%RaceCategory{
    name: "Elite Men",
    gender: :male,
    sort_order: 1,
    race_id: race.id,
    inserted_at: now,
    updated_at: now
  })

cat_elite_women =
  Repo.insert!(%RaceCategory{
    name: "Elite Women",
    gender: :female,
    sort_order: 2,
    race_id: race.id,
    inserted_at: now,
    updated_at: now
  })

cat_age_group =
  Repo.insert!(%RaceCategory{
    name: "Age Group",
    gender: :any,
    sort_order: 3,
    race_id: race.id,
    inserted_at: now,
    updated_at: now
  })

IO.puts("Created 3 race categories")

# ---------------------------------------------------------------------------
# 4. Splits
# ---------------------------------------------------------------------------
split_swim =
  Repo.insert!(%Split{
    name: "Swim Finish",
    short_name: "SWIM",
    leg_type: :swim,
    sort_order: 1,
    race_id: race.id,
    inserted_at: now,
    updated_at: now
  })

split_t1 =
  Repo.insert!(%Split{
    name: "T1 Out",
    short_name: "T1",
    leg_type: :transition,
    sort_order: 2,
    race_id: race.id,
    inserted_at: now,
    updated_at: now
  })

split_bike =
  Repo.insert!(%Split{
    name: "Bike Finish",
    short_name: "BIKE",
    leg_type: :bike,
    sort_order: 3,
    race_id: race.id,
    inserted_at: now,
    updated_at: now
  })

split_t2 =
  Repo.insert!(%Split{
    name: "T2 Out",
    short_name: "T2",
    leg_type: :transition,
    sort_order: 4,
    race_id: race.id,
    inserted_at: now,
    updated_at: now
  })

split_run =
  Repo.insert!(%Split{
    name: "Run Finish",
    short_name: "RUN",
    leg_type: :run,
    sort_order: 5,
    race_id: race.id,
    inserted_at: now,
    updated_at: now
  })

splits = [split_swim, split_t1, split_bike, split_t2, split_run]

IO.puts("Created 5 splits")

# ---------------------------------------------------------------------------
# 5. Participants (15 total)
# ---------------------------------------------------------------------------
participants_data = [
  # Elite Men (bibs 1-5)
  %{
    bib: "1",
    first: "Erik",
    last: "Lindqvist",
    gender: :male,
    club: "Malmö TK",
    category: cat_elite_men
  },
  %{
    bib: "2",
    first: "Anders",
    last: "Johansson",
    gender: :male,
    club: "Lunds TK",
    category: cat_elite_men
  },
  %{
    bib: "3",
    first: "Niklas",
    last: "Bergström",
    gender: :male,
    club: "Helsingborgs TK",
    category: cat_elite_men
  },
  %{
    bib: "4",
    first: "Johan",
    last: "Svensson",
    gender: :male,
    club: "Göteborgs Triathlon",
    category: cat_elite_men
  },
  %{
    bib: "5",
    first: "Marcus",
    last: "Karlsson",
    gender: :male,
    club: "Stockholms TK",
    category: cat_elite_men
  },

  # Elite Women (bibs 6-10)
  %{
    bib: "6",
    first: "Emma",
    last: "Nilsson",
    gender: :female,
    club: "Lunds TK",
    category: cat_elite_women
  },
  %{
    bib: "7",
    first: "Sara",
    last: "Eriksson",
    gender: :female,
    club: "Malmö TK",
    category: cat_elite_women
  },
  %{
    bib: "8",
    first: "Anna",
    last: "Petersson",
    gender: :female,
    club: "Helsingborgs TK",
    category: cat_elite_women
  },
  %{
    bib: "9",
    first: "Karin",
    last: "Olsson",
    gender: :female,
    club: "Göteborgs Triathlon",
    category: cat_elite_women
  },
  %{
    bib: "10",
    first: "Maja",
    last: "Andersson",
    gender: :female,
    club: "Stockholms TK",
    category: cat_elite_women
  },

  # Age Group (bibs 11-15)
  %{
    bib: "11",
    first: "Lars",
    last: "Gustafsson",
    gender: :male,
    club: "Lunds CK",
    category: cat_age_group
  },
  %{
    bib: "12",
    first: "Ingrid",
    last: "Hansson",
    gender: :female,
    club: "Malmö Runners",
    category: cat_age_group
  },
  %{
    bib: "13",
    first: "Per",
    last: "Ström",
    gender: :male,
    club: "Helsingborgs SK",
    category: cat_age_group
  },
  %{
    bib: "14",
    first: "Maria",
    last: "Larsson",
    gender: :female,
    club: "Lunds TK",
    category: cat_age_group
  },
  %{
    bib: "15",
    first: "Gustav",
    last: "Nordström",
    gender: :male,
    club: "Malmö TK",
    category: cat_age_group
  }
]

participants =
  Enum.map(participants_data, fn p ->
    Repo.insert!(%Participant{
      bib_number: p.bib,
      first_name: p.first,
      last_name: p.last,
      gender: p.gender,
      club: p.club,
      status: :registered,
      race_id: race.id,
      race_category_id: p.category.id,
      inserted_at: now,
      updated_at: now
    })
  end)

IO.puts("Created 15 participants")

# ---------------------------------------------------------------------------
# 6. Race start
# ---------------------------------------------------------------------------
# Set gun start to ~1 hour ago so the elapsed clock shows a realistic time
gun_start = DateTime.utc_now() |> DateTime.add(-3600, :second) |> DateTime.truncate(:microsecond)

Repo.insert!(%RaceStart{
  started_at: gun_start,
  wave_name: "Mass Start",
  race_id: race.id,
  inserted_at: now,
  updated_at: now
})

IO.puts("Created race start")

# ---------------------------------------------------------------------------
# 7. Split times (partial to simulate race in progress)
# ---------------------------------------------------------------------------

# Helper to insert a split time
insert_split_time = fn participant, split, elapsed_ms ->
  Repo.insert!(%SplitTime{
    elapsed_ms: elapsed_ms,
    source: :manual,
    participant_id: participant.id,
    split_id: split.id,
    inserted_at: now
  })
end

# Realistic cumulative elapsed times in milliseconds for sprint triathlon:
#   Swim:       ~15-20 min  => 900_000 - 1_200_000 ms
#   T1:         ~1.5-2.5 min => +90_000 - 150_000 ms
#   Bike:       ~35-50 min  => +2_100_000 - 3_000_000 ms
#   T2:         ~0.5-1.5 min => +30_000 - 90_000 ms
#   Run:        ~20-35 min  => +1_200_000 - 2_100_000 ms

# --- Finished participants (bibs 1-5, all 5 splits) ---
# Bib 1 - Erik Lindqvist (fast elite male)
# 15:12
insert_split_time.(Enum.at(participants, 0), split_swim, 912_000)
# +1:30
insert_split_time.(Enum.at(participants, 0), split_t1, 1_002_000)
# +36:00
insert_split_time.(Enum.at(participants, 0), split_bike, 3_162_000)
# +0:42
insert_split_time.(Enum.at(participants, 0), split_t2, 3_204_000)
# +21:30
insert_split_time.(Enum.at(participants, 0), split_run, 4_494_000)

# Bib 2 - Anders Johansson
# 15:48
insert_split_time.(Enum.at(participants, 1), split_swim, 948_000)
# +1:42
insert_split_time.(Enum.at(participants, 1), split_t1, 1_050_000)
# +38:00
insert_split_time.(Enum.at(participants, 1), split_bike, 3_330_000)
# +0:48
insert_split_time.(Enum.at(participants, 1), split_t2, 3_378_000)
# +22:30
insert_split_time.(Enum.at(participants, 1), split_run, 4_728_000)

# Bib 6 - Emma Nilsson (fast elite female)
# 16:00
insert_split_time.(Enum.at(participants, 5), split_swim, 960_000)
# +1:48
insert_split_time.(Enum.at(participants, 5), split_t1, 1_068_000)
# +40:00
insert_split_time.(Enum.at(participants, 5), split_bike, 3_468_000)
# +0:54
insert_split_time.(Enum.at(participants, 5), split_t2, 3_522_000)
# +24:00
insert_split_time.(Enum.at(participants, 5), split_run, 4_962_000)

# Bib 7 - Sara Eriksson
# 17:00
insert_split_time.(Enum.at(participants, 6), split_swim, 1_020_000)
# +1:48
insert_split_time.(Enum.at(participants, 6), split_t1, 1_128_000)
# +41:00
insert_split_time.(Enum.at(participants, 6), split_bike, 3_588_000)
# +1:00
insert_split_time.(Enum.at(participants, 6), split_t2, 3_648_000)
# +26:00
insert_split_time.(Enum.at(participants, 6), split_run, 5_208_000)

# Bib 11 - Lars Gustafsson (age group)
# 19:00
insert_split_time.(Enum.at(participants, 10), split_swim, 1_140_000)
# +2:12
insert_split_time.(Enum.at(participants, 10), split_t1, 1_272_000)
# +46:00
insert_split_time.(Enum.at(participants, 10), split_bike, 4_032_000)
# +1:18
insert_split_time.(Enum.at(participants, 10), split_t2, 4_110_000)
# +30:00
insert_split_time.(Enum.at(participants, 10), split_run, 5_910_000)

# --- Mid-race participants (bibs 3, 8, 12: 3 splits; bibs 4, 9: 2 splits) ---
# Bib 3 - Niklas Bergström (through bike)
# 15:30
insert_split_time.(Enum.at(participants, 2), split_swim, 930_000)
# +1:36
insert_split_time.(Enum.at(participants, 2), split_t1, 1_026_000)
# +37:00
insert_split_time.(Enum.at(participants, 2), split_bike, 3_246_000)

# Bib 8 - Anna Petersson (through bike)
# 17:30
insert_split_time.(Enum.at(participants, 7), split_swim, 1_050_000)
# +2:00
insert_split_time.(Enum.at(participants, 7), split_t1, 1_170_000)
# +42:00
insert_split_time.(Enum.at(participants, 7), split_bike, 3_690_000)

# Bib 12 - Ingrid Hansson (through bike, age group)
# 20:00
insert_split_time.(Enum.at(participants, 11), split_swim, 1_200_000)
# +2:30
insert_split_time.(Enum.at(participants, 11), split_t1, 1_350_000)
# +50:00
insert_split_time.(Enum.at(participants, 11), split_bike, 4_350_000)

# Bib 4 - Johan Svensson (through T1)
# 15:54
insert_split_time.(Enum.at(participants, 3), split_swim, 954_000)
# +1:48
insert_split_time.(Enum.at(participants, 3), split_t1, 1_062_000)

# Bib 9 - Karin Olsson (through T1)
# 18:00
insert_split_time.(Enum.at(participants, 8), split_swim, 1_080_000)
# +2:12
insert_split_time.(Enum.at(participants, 8), split_t1, 1_212_000)

# --- Swim-only participants (bibs 5, 10, 13, 14, 15) ---
# Bib 5 - Marcus Karlsson
# 16:12
insert_split_time.(Enum.at(participants, 4), split_swim, 972_000)

# Bib 10 - Maja Andersson
# 18:12
insert_split_time.(Enum.at(participants, 9), split_swim, 1_092_000)

# Bib 13 - Per Ström
# 19:24
insert_split_time.(Enum.at(participants, 12), split_swim, 1_164_000)

# Bib 14 - Maria Larsson
# 19:48
insert_split_time.(Enum.at(participants, 13), split_swim, 1_188_000)

# Bib 15 - Gustav Nordström
# 18:36
insert_split_time.(Enum.at(participants, 14), split_swim, 1_116_000)

# Mark participants with all 5 splits as finished, those with partial splits as racing
finished_indices = [0, 1, 5, 6, 10]
racing_indices = [2, 3, 4, 7, 8, 9, 11, 12, 13, 14]

for i <- finished_indices do
  Bibtime.Participants.mark_finished(Enum.at(participants, i))
end

for i <- racing_indices do
  Bibtime.Participants.update_participant(Enum.at(participants, i), %{status: :racing})
end

IO.puts("Created split times for race in progress")
IO.puts("Seed data complete!")
