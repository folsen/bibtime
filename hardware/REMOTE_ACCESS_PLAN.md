# Remote Access Plan — SSH Into Stations Over 4G

Plan for getting reliable, ad-hoc SSH access to deployed timing stations,
including ones behind CGNAT on a 4G modem. Status: **proposed, not yet
implemented.**

## Goal

Be able to type `ssh bibtime@bibtime-1` from a laptop and land on any
station, anywhere on the planet, while it is powered on and has any
working internet connection (WiFi, 4G, tethered phone). This needs to
work during a live race for triage, and during pre-race test deployments
for iteration without driving to the venue.

The station should also report its connectivity state back to the BibTime
server so the admin dashboard can answer "is this station reachable from
my desk right now?" without needing to actually try to SSH in.

## Non-goals

- Pushing code/firmware updates over the link. The existing
  `deploy/deploy.sh` flow can use the same SSH transport, but no new
  auto-update machinery is in scope here.
- A full VPN for arbitrary services. Only SSH (and incidentally anything
  else bound to the tunnel interface) — we are not exposing the station
  HTTP server, the R200 over network serial, etc.
- Bypassing the BibTime server for chip reads. Reads still go over plain
  HTTPS; the tunnel is purely a sidecar for ops.

## Why Tailscale

Briefly evaluated three options:

| Approach | Works through CGNAT | Cost | Setup effort | Lock-in |
|----------|---------------------|------|--------------|---------|
| **Tailscale** | Yes — coordinated NAT traversal + DERP relays | Free up to 100 devices, 3 users | Low | Tailscale control plane (open-source alternative: Headscale) |
| Reverse SSH tunnel to a VPS | Yes | ~$5/mo VPS + babysitting | Medium (autossh, systemd hardening, key rotation) | None, but you own the VPS |
| Static-IP IoT SIM | Yes | ~€5-15/SIM/mo, carrier-locked | Low (just the SIM) | One carrier per fleet |

Tailscale wins on day-one effort and "it just works" through CGNAT. The
free tier covers our entire foreseeable fleet (we'll have tens of
stations, not hundreds). If we ever want to drop the dependency, we can
self-host **Headscale** with the same client binaries — no station-side
code changes needed.

The reverse-SSH-to-VPS option remains the fallback if Tailscale is ever
blocked by a venue's network (some restrictive corporate WiFi blocks the
DERP relays' UDP/443).

## Architecture

```
┌─────────────────┐   WireGuard (UDP)    ┌─────────────────┐
│  Laptop         │ ◄──────────────────► │  Pi station     │
│  Tailscale      │   direct or via      │  Tailscale +    │
│  100.64.0.2     │   DERP relay         │  sshd           │
└─────────────────┘                       │  100.64.0.10    │
       │                                  └────────┬────────┘
       │ ssh bibtime@bibtime-1 (MagicDNS)          │
       │                                            │ heartbeat
       ▼                                            ▼ (existing path)
                                            ┌─────────────────┐
                                            │ BibTime server  │
                                            │ shows tailnet   │
                                            │ IP + status in  │
                                            │ admin UI        │
                                            └─────────────────┘
```

The SSH path and the chip-read path are independent. Tailscale being
down does not stop reads from being uploaded; the chip-read API being
down does not stop us from SSH'ing in to debug.

## Tailscale Configuration

### Account & tailnet

- One **Tailscale tailnet** owned by the BibTime org account (not a
  personal account — tied to a shared `ops@` mailbox so the account
  outlives any one person).
- Free plan to start. No need for SSO / Custom OIDC unless we add more
  ops users than the free tier allows.

### Tags

Use ACL tags rather than per-user identities for stations. This keeps
stations machine-owned, not tied to whoever provisioned them.

| Tag | Applied to | Purpose |
|-----|------------|---------|
| `tag:station` | Every Pi | Source/destination in ACLs; auth keys mint nodes with this tag |
| `tag:ops` | Operator laptops | Allows SSH into `tag:station` |
| `tag:server` | The BibTime production server (optional) | If we want the server to reach stations directly, e.g. for live config push |

### ACL policy (sketch)

```hujson
{
  "tagOwners": {
    "tag:station": ["autogroup:admin"],
    "tag:ops":     ["autogroup:admin"],
    "tag:server":  ["autogroup:admin"]
  },
  "acls": [
    // Operators can SSH into any station
    { "action": "accept", "src": ["tag:ops"], "dst": ["tag:station:22"] },

    // Stations cannot talk to each other or to operator machines
    // (omitted = deny by default)

    // Optional: server can reach station SSH for automation
    { "action": "accept", "src": ["tag:server"], "dst": ["tag:station:22"] }
  ],
  "ssh": [
    // Use Tailscale SSH instead of OS sshd authn — keys managed by tailnet
    {
      "action": "accept",
      "src": ["tag:ops"],
      "dst": ["tag:station"],
      "users": ["bibtime", "root"]
    }
  ]
}
```

Decision to make: **OS sshd vs Tailscale SSH.** Tailscale SSH means we
don't ship SSH keys to every Pi — Tailscale handles authn from the
tailnet identity. But it requires `tailscale up --ssh` and means the
sshd config on the Pi becomes irrelevant to the access path. Probably
worth using; falls back to plain OS sshd if we ever disable Tailscale.

### Auth keys

Each station needs an auth key to register itself. Two strategies:

1. **One-shot keys per Pi** during provisioning. Best security; manual
   step per device.
2. **Reusable, pre-authorized, tagged auth key.** Stored as a secret in
   the provision script; any Pi running provision joins the tailnet
   automatically with `tag:station`. Easier ops, slightly bigger blast
   radius if leaked.

Recommendation: **reusable + tagged + 90-day expiry**, rotated when an
operator leaves. Set `ephemeral=false` (we want the node to keep its
identity across reboots) and `preauthorized=true`.

Store the key only in a password manager / 1Password vault entry called
`tailscale-station-authkey`. The provision script prompts for it
interactively rather than reading from disk.

### MagicDNS

Enable in tailnet admin. Stations get `bibtime-1.<tailnet>.ts.net`. Set
the Pi's tailnet hostname to its `hostname` (e.g. `bibtime-1`) during
`tailscale up` so DNS lines up with how we already name them.

## Pi-Side Implementation

### Install Tailscale

Add to `bibtime_station/deploy/provision.sh`, after the existing apt
install block:

```bash
ssh "$HOST" bash <<'REMOTE'
set -euo pipefail

if ! command -v tailscale >/dev/null 2>&1; then
  curl -fsSL https://tailscale.com/install.sh | sh
fi

sudo systemctl enable --now tailscaled
REMOTE
```

The Tailscale install script handles armv6/aarch64 detection itself.

### Bring the tunnel up

Append to provision.sh, prompting for the auth key:

```bash
read -rsp "Tailscale auth key (tskey-auth-...): " TS_AUTHKEY
echo

ssh "$HOST" sudo tailscale up \
  --authkey="$TS_AUTHKEY" \
  --ssh \
  --hostname="$1" \
  --advertise-tags=tag:station \
  --accept-dns=false
```

`--accept-dns=false` so MagicDNS doesn't override `/etc/resolv.conf` on
the Pi (we don't want station-side resolution to depend on the tailnet
being up). `--ssh` enables Tailscale SSH (assuming we go with that
decision above). `--hostname` keeps the tailnet name aligned with the
provisioning hostname.

### Service ordering

Tailscale's `tailscaled.service` ships with appropriate ordering already.
The `bibtime_station.service` does not need to wait for it — chip reads
should attempt to upload via the public internet and only fall back to
the buffer if that fails, which is the same behaviour we have today.

If we later want the server-side endpoints reachable *only* through the
tailnet, that ordering becomes load-bearing; for now, leave them
independent.

### Heartbeat additions

`bibtime_station/lib/bibtime_station/heartbeat.ex` currently reports
firmware/uptime/reads/buffer/reader fields. Extend `build_payload/1`
with three new fields:

| Field | Source | Notes |
|-------|--------|-------|
| `local_ip` | First non-loopback IPv4 from `:inet.getifaddrs/0`, preferring `wlan0` then `usb*`/`wwan*` then anything else | Useful for LAN debugging; falls back to whatever interface the Pi is using |
| `tailscale_ip` | `tailscale ip -4` via `System.cmd/2`, or `nil` if the binary is missing / errors | Stable per-device once registered |
| `tailscale_status` | `online` if `tailscale status --json` reports a backend `Running` state with a self IP, else `offline` (or `not_installed`) | Surfaces tunnel health distinct from chip-read API health |

Keep the lookup cheap: cache for ~30 s. Tailscale IP doesn't change
unless the device is re-keyed; refreshing it once per minute is plenty.

Pseudocode:

```elixir
defp tailscale_info do
  case System.cmd("tailscale", ["status", "--json"], stderr_to_stdout: true) do
    {json, 0} ->
      decoded = Jason.decode!(json)
      ip = decoded |> Map.get("Self", %{}) |> Map.get("TailscaleIPs", []) |> List.first()
      state = if decoded["BackendState"] == "Running", do: "online", else: "offline"
      {ip, state}

    {_, _} ->
      {nil, "not_installed"}
  end
rescue
  ErlangError -> {nil, "not_installed"}
end
```

Wrap in a small `Agent` or memoize via `:persistent_term` with a
timestamp — do not shell out on every heartbeat tick (10 s).

### Tests

Add a unit test for `Heartbeat.build_payload/1` that injects a fake
`tailscale_info` resolver via opts, asserting the new fields appear in
the payload. Mirrors how `http_client` is already overridable.

## Server-Side Implementation

### Whitelist new heartbeat fields

`lib/bibtime_web/controllers/api/station_controller.ex:67` — add
`"local_ip"`, `"tailscale_ip"`, `"tailscale_status"` to the
`Map.take/2` keys list. The metadata column is already `:map`, so no
schema migration needed.

### Surface in admin UI

`Admin.StationLive.GlobalIndex` (route `/admin/stations`) is the
natural place. Add a column or row-detail showing:

- **Tailnet IP** as a copyable monospace string
- **One-click SSH command** (`ssh bibtime@bibtime-1`) — render as
  `<code>` next to a clipboard button. We deliberately do NOT auto-open
  ssh:// URLs; just make copy easy.
- **Tunnel status pill** (green/orange/grey for online/offline/not-installed)

`Admin.StationLive.Index` (per-race) gets the same pill, smaller — no
need for the SSH command on the race-day dashboard, the timer doesn't
care.

Gettext: any new strings must go through `gettext()` per CLAUDE.md.

### No PubSub changes

The existing `"race:stations:#{race_id}"` topic already broadcasts
heartbeat updates. The new fields ride along automatically.

## Provisioning Flow (end-to-end)

After the changes:

```
1. Flash Pi with Imager (existing step — sets hostname, SSH key)
2. ./deploy/provision.sh bibtime-1
     → installs Erlang/Elixir/build-essential
     → installs tailscale, prompts for auth key, brings tunnel up
     → installs systemd unit, env template, USB fix
     → enables gpio-shutdown overlay
3. Edit /etc/default/bibtime_station: BIBTIME_URL, STATION_TOKEN
4. ./deploy/deploy.sh bibtime-1
     → mix release, rsync to Pi, restart service
5. Confirm in admin UI: tailscale_status=online, tailscale_ip=100.x.y.z
6. From laptop: ssh bibtime@bibtime-1   ← works from anywhere
```

## Operational Runbook

### Day-to-day

- Adding a new operator: invite their email to the tailnet, assign
  `tag:ops`, they install Tailscale on their machine. Done.
- Removing an operator: remove from tailnet. Their machine instantly
  loses access; no per-station key rotation needed.
- Rotating the station auth key: generate a new one in the Tailscale
  admin, update the password manager entry, kill the old key. New Pis
  use the new key; existing Pis are unaffected (they have node keys,
  not auth keys).

### Lost / stolen Pi

1. Open Tailscale admin → Machines → find the Pi → **Remove**.
   Immediately revokes the tunnel.
2. In BibTime admin: rotate `STATION_TOKEN` for that station so its
   chip-read API access is also dead.
3. (Both should be done — Tailscale removal doesn't stop the Pi from
   POSTing reads over the public internet.)

### "I can't SSH in" triage

Order of checks:

1. Admin UI: is `tailscale_status=online`? If not, the Pi can't reach
   the Tailscale control plane — likely no internet, check the chip-read
   heartbeat status too.
2. `tailscale status` from your laptop: is the station listed and
   reachable (no `(idle, no route)`)?
3. `tailscale ping bibtime-1` — distinguishes routing vs SSH service
   issues.
4. If routing is fine but SSH hangs: the Pi is up enough to maintain
   the tunnel but sshd / Tailscale SSH is wedged. Plan a power-cycle.

### When Tailscale itself is the problem

Some venues block the DERP relays. Symptoms: tunnel comes up, peer
shows online, but `tailscale ping` fails or only succeeds over relay
with high latency.

Mitigations:
- Tether the Pi to a phone hotspot temporarily.
- Fall back to physical access — the gpio-shutdown button still works.
- (Long-term) deploy a fallback reverse-SSH tunnel to a VPS, only
  activated when Tailscale is down. Not in scope for v1.

## Security Considerations

- **Tailscale auth key in the provision script**: prompted, not stored.
  Operator pastes it from 1Password each provisioning run. Don't commit
  it, don't log it.
- **Tailscale SSH** removes the per-Pi SSH key management problem but
  centralises trust in the tailnet identity layer. ACLs above restrict
  station-to-station and station-to-operator traffic so a compromised
  Pi cannot pivot.
- **Audit log**: Tailscale logs SSH sessions in the admin console.
  Consider mirroring "operator X SSH'd into station Y" events into our
  `AuditLog` context if we ever want them in the BibTime UI — out of
  scope for v1.
- **Heartbeat metadata is public-ish**: anything we put in `metadata`
  is visible to any timer/admin user looking at the station dashboard.
  The tailnet IP is not a secret (it's only routable from the tailnet),
  so this is fine. Don't put auth keys, node keys, or anything similar
  there.

## Cost & Limits

- Tailscale Free: 100 devices, 3 users, unlimited tailnets. We are
  comfortably inside this.
- If we cross 100 devices: Personal Pro is $5/user/mo and goes to 100
  devices per user. Business plan ($6/user/mo) raises to higher limits
  and adds SSO.
- DERP bandwidth is metered on paid plans for high volumes; SSH traffic
  for ops is negligible.

## Open Questions

1. **Tailscale SSH or plain sshd?** Recommend Tailscale SSH for v1, but
   it does mean we depend on Tailscale for authn, not just transport.
   If a venue blocks Tailscale we lose SSH entirely. Plain sshd over
   the tunnel keeps OS-level keys as a fallback.
2. **Do we want subnet routing?** If we add a wired LAN at the venue
   with non-Tailscale gear (e.g. a managed switch we want to hit), one
   station could `--advertise-routes` for the venue subnet. Probably
   YAGNI.
3. **Headscale fallback**: pre-decide whether we'd self-host Headscale
   if Tailscale changes pricing/policy, or move to the reverse-SSH
   approach. Documenting now is cheap; switching later is cheaper if
   we have written it down.
4. **Station-initiated server access?** Currently the station only
   makes outbound HTTP. Tailscale would let the server reach into the
   station for, e.g., live R200 power-level adjustment. Tempting but
   widens the blast radius — leave for a follow-up.

## Rollout

1. Land code changes (heartbeat fields, server whitelist, admin UI) in
   a single PR. They're harmless without Tailscale installed —
   `tailscale_status` just reports `not_installed`.
2. Set up Tailscale tailnet, ACLs, auth key, get one operator on it.
3. Provision one Pi end-to-end against a staging BibTime, confirm SSH
   works from a tethered phone (forces 4G + CGNAT path).
4. Roll over existing deployed Pis: `ssh` in once with current method
   (LAN), run a one-shot `tailscale up …`, verify in admin UI.
5. Document SSH-via-Tailscale in `bibtime_station/DEPLOYMENT.md` and
   strike the LAN-only assumption.

## Files Touched (when we implement)

- `bibtime_station/lib/bibtime_station/heartbeat.ex` — add
  local_ip/tailscale_ip/tailscale_status to payload, with caching.
- `bibtime_station/test/bibtime_station/heartbeat_test.exs` — assert
  new fields, allow injection of a fake tailscale resolver.
- `bibtime_station/deploy/provision.sh` — install Tailscale, prompt
  for auth key, run `tailscale up`.
- `bibtime_station/DEPLOYMENT.md` — document the new flow.
- `lib/bibtime_web/controllers/api/station_controller.ex` — whitelist
  new metadata keys.
- `lib/bibtime_web/live/admin/station_live/global_index.ex` (+ heex) —
  show tailnet IP, SSH command, tunnel status pill.
- `lib/bibtime_web/live/admin/station_live/index.ex` (+ heex) — small
  status pill.
- `priv/gettext/default.pot` + `priv/gettext/sv/LC_MESSAGES/default.po`
  — translations for new strings (`mix gettext.extract --merge`).

No DB migration. No new dependencies on the Elixir side (Tailscale is
shelled out to, not linked).
