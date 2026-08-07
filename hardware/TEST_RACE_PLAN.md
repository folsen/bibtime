# Test Race Plan — Stations 2 & 3, Remote Access, Full Dry Run

Getting from "stations 2 and 3 assembled but unprovisioned" to a full
test race that is as close to reality as possible. Networking decision:
**Tailscale** (per [REMOTE_ACCESS_PLAN.md](REMOTE_ACCESS_PLAN.md)) — iroh
is a p2p library that would need custom tunnel glue for SSH access and
has no device-management/ACL story; not worth it for a fleet of three
Pis.

Legend: **[Me]** = Claude can do it from the repo/terminal · **[You]** =
needs hands, browser accounts, or physical hardware.

## 1. Remote-access code + provisioning script — [Me]

Implement the code side of REMOTE_ACCESS_PLAN.md:

- [x] `bibtime_station/lib/bibtime_station/heartbeat.ex`: add
      `local_ip`, `tailscale_ip`, `tailscale_status` to the heartbeat
      payload (cached ~30 s, injectable resolver for tests).
- [x] `bibtime_station` tests for the new payload fields.
- [x] Server: whitelist the three new metadata keys in
      `BibtimeWeb.API.StationController`.
- [x] Admin UI: tunnel-status pill + tailnet IP + copyable
      `ssh bibtime@<host>` on `/admin/stations`; small status pill on
      the per-race station page.
- [x] `bibtime_station/deploy/provision.sh`: install Tailscale, prompt
      for auth key, `tailscale up --ssh --hostname=<name>
      --advertise-tags=tag:station --accept-dns=false`.
- [x] Update `bibtime_station/DEPLOYMENT.md`; gettext extract + Swedish.

All of this is inert until Tailscale is actually installed on a Pi
(`tailscale_status` shows "not installed").

## 2. Tailnet setup — [You] (~15 min)

- [x] Create the tailnet — org/ops account rather than personal.
- [x] Enable MagicDNS.
- [x] Paste the ACL policy from REMOTE_ACCESS_PLAN.md (tags
      `tag:station`, `tag:ops`; Tailscale SSH enabled for ops → station).
- [x] Generate a **reusable, pre-authorized, tagged (`tag:station`),
      90-day** auth key; store in password manager
      (`tailscale-station-authkey`).
- [x] Install Tailscale on your laptop; tag it `tag:ops`.

## 3. Flash + provision stations 2 and 3

- [x] **[You]** Raspberry Pi Imager on both SD cards: Pi OS Lite
      (64-bit), hostname `bibtime-station-2` / `bibtime-station-3`, username `bibtime`,
      your WiFi + country `SE`, SSH enabled with your pubkey. Insert
      cards, power on, confirm they appear on the LAN.
      **SSID must be `Mick Schumacher`** (the 2.4 GHz network station 1
      uses) — the first flash used `Valtteri Bottas`, which the
      Pi Zero 2 W never joined, and cards had to be re-flashed.
- [x] **[Me]** Run `./deploy/provision.sh` (station 3 done; station 2
      in flight). Auth key comes from `TS_AUTHKEY` in `.env`.
- [x] **[Me]** Station records created on staging; station 1 + 3
      configured with `BIBTIME_URL=https://bibtime-staging.fly.dev` +
      tokens; station 1 retrofitted (Tailscale + new station code).
- [x] **[Me]** Deploys done for 1 + 3 — both online on staging with
      `tailscale_status=online`, readers connected. (Fixed a deploy.sh
      bug where Hex's advisory prompt silently ate the build, and a
      routing bug where a data-less 4G modem hijacked the default
      route — modem now demoted to backup with its DNS ignored.)
- [x] **[Me]** Station 2: provisioned + deployed (finished by IP after
      its mDNS dropped mid-run — that unit's WiFi looks weak, worth
      watching; its 4G modem also never presented an eth0 interface).
- [ ] **[You]** Sanity check: `ssh bibtime@bibtime-station-2` from your laptop
      over the tailnet (try once on phone hotspot to exercise the
      CGNAT path).

## 4. Test race setup in BibTime — [Me]

- [x] Target server: **staging** (`bibtime-staging.fly.dev`), running
      current main (multi-split + read log).
- [x] Test race created: **"Dry Run Test Race"** (`dry-run-test`,
      race_id 3, in_progress). Splits: Swim Exit · Bike Start ·
      Bike Exit · Run Start · Run Finish.
- [x] Stations assigned: 1 → Swim Exit · 2 → Bike Start + Bike Exit ·
      3 → Run Start + Run Finish. Lockout lowered to **30 s** on
      stations 2 and 3 (walking-pace dry run — keep >30 s between
      passes at the same station or the re-read guard eats the pass).
- [x] Participants registered: bibs 1–4 ("Test Runner One…Four").

## 5. Chip check-in — [You]

- [ ] Assign real chips to test participants via the check-in screen
      (or send Claude the tag EPCs and it does the mapping).

## 6. Dry run — [Together]

- [ ] **[You]** Position and power all three stations, start the race,
      then walk tags past antennas in race order — plus the nasty
      cases: linger in a read zone, skip a pass entirely, walk
      backwards through a mat.
- [ ] **[Me]** Watch station dashboard, timing console, flagged
      entries, and server logs; verify split attribution, lockout
      behavior, review flags, and final results.
- [ ] **[Together]** Debrief; file/fix whatever broke.

## Sequencing

Steps 1 and 2 can run in parallel today. 3 needs 2 (auth key). 4 can
happen anytime. 5–6 once hardware is in position.
