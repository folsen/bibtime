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

- [ ] **[You]** Raspberry Pi Imager on both SD cards: Pi OS Lite
      (64-bit), hostname `bibtime-station-2` / `bibtime-station-3`, username `bibtime`,
      your WiFi + country `SE`, SSH enabled with your pubkey. Insert
      cards, power on, confirm they appear on the LAN.
- [ ] **[Me]** Run `./deploy/provision.sh bibtime-station-2.local` (and `-3`)
      — you paste the Tailscale auth key at the prompt.
- [ ] **[Me]** Create station records in the admin UI, set
      `BIBTIME_URL` + `STATION_TOKEN` in `/etc/default/bibtime_station`
      on each Pi.
- [ ] **[Me]** `./deploy/deploy.sh` both Pis; verify they flip online
      on the stations dashboard and `tailscale_status=online`.
- [ ] **[You]** Sanity check: `ssh bibtime@bibtime-station-2` from your laptop
      over the tailnet (try once on phone hotspot to exercise the
      CGNAT path).

## 4. Test race setup in BibTime — [Me]

- [ ] Decide target server: staging vs production (**[You]** call —
      production is closest to reality).
- [ ] Create the test race with the real split layout, e.g.:
      station 1 = swim exit · station 2 = bike start **and** bike exit ·
      station 3 = run start **and** run finish (exercises the new
      multi-split assignment + lockout).
- [ ] Assign stations to splits; review `pass_lockout_seconds` per
      station (default 120 s — lower it if two passes at one mat can
      legitimately be closer).
- [ ] Register test participants.

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
