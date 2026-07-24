# niflheim

Offsite backup box — copy #3 of the 3-2-1 for draupnir's irreplaceable data.
**Design of record: `docs/immich-offsite-backup-plan.md`** (read it before
touching anything here). This file is the host-local topology + the
scaffold/TODO state.

## Role in one paragraph

An **intermittently-connected** low-power mini-PC at a **second physical
location**. It is powered on **~once a month**, pulls a **raw** (`zfs send -w`,
end-to-end encrypted) replica of `tank/{immich,backups}` from draupnir into a
local single-disk pool `cold`, prunes to a deep retention, ntfy's the result,
and **powers itself back off**. It never holds `tank`'s encryption key, so the
copy is ciphertext at rest and unreadable on the box itself.

## Topology (planned)

- **OS:** NVMe, plain BTRFS via `../common/disks/btrfs-disk-uefi.nix` (no LUKS,
  no wipe) — same as draupnir.
- **Data:** the **whole HDD** as a single-disk, **unencrypted** ZFS pool `cold`
  (`disko-data.nix`). No redundancy — accepted, because the pool is
  reconstructible from draupnir (re-seed on LAN if the disk dies). Received
  datasets are their own encryption roots inside the plain pool.
- **Network:** **DHCP**, no static LAN IP (the box relocates). Addresses via
  tailscale everywhere. Tailnet member via `../optional/tailscale.nix`.
- **Snapshots:** prune-only sanoid (`services/sanoid.nix`), `autosnap = false` —
  every snapshot arrives via syncoid. Retention 0h/30d/24m/**10y** (deeper than
  home; decoupled — syncoid never propagates draupnir's deletions).
- **Replication:** `services/syncoid.nix` — a run-on-connect systemd service
  that pulls, prunes, notifies, powers off; retries with a "still failing after
  ~1h" ntfy.
- **Bookmark base:** the incremental anchor is a **bookmark** on draupnir (not a
  hold) — zero-space, so a long niflheim absence never bloats `tank`. draupnir's
  `syncoid` user has `send,snapshot,bookmark,mount` delegated (no `destroy`, no
  `hold`).

## Monitoring split

- niflheim → ntfy `backup-niflheim`: **"sync OK"** (each success) + **"still
  failing"** (on but stuck >1h).
- draupnir → ntfy: the **staleness watchdog** (the piece niflheim can't own,
  since a powered-off box can't heartbeat). Alerts if the newest `syncoid`
  bookmark on `tank/immich` is > 45 days old. Lives on draupnir (always-on).

## SCAFFOLD status — what's left before this host is real

The flake `nixosConfigurations.niflheim` entry is **commented out** until:

1. **Hardware exists** — fill every `TODO(hw)`:
   - `hardware-configuration.nix` — regenerate on the box.
   - `disko-data.nix` / `default.nix` — real `/dev/disk/by-id` for the HDD and
     the NVMe.
   - `default.nix` — real random `hostId`; confirm `system.stateVersion`.
2. **Secrets** — every `TODO(sops)`:
   - Pre-generate the host SSH key, commit `ssh_host_ed25519_key.pub`, add
     `&niflheim` to `.sops.yaml`, then `sops hosts/niflheim/secrets.yaml` with
     `syncoid/ssh-key` (private key for `syncoid@draupnir`) and
     `syncoid/ntfy-token`.
3. **Draupnir side** (plan Phase 2) — create the `syncoid` user + `zfs allow`
   delegation + authorized key; create the `backup-niflheim` ntfy topic/token.
4. **Uncomment** the flake entry and install via nixos-anywhere on the home LAN
   (draupnir pattern), then **seed** (plan Phase 4).

## Gotchas to resolve at bring-up

- **accept-routes offsite vs the LAN trap.** Offsite, niflheim must
  `accept-routes` to reach `ntfy.lan.valgrindr.net` (AdGuard rewrite + bifrost
  subnet route). But during the *home-LAN seed* it is temporarily LAN-resident —
  accepting its own LAN's `192.168.1.0/24` route can blackhole inbound replies
  (see the accept-routes LAN trap note). The seed talks to draupnir over
  `100.64.0.13`, so that's fine; just be aware when validating ntfy from the
  offsite site later.
- **Raw incremental from a bookmark needs OpenZFS ≥ 2.1** — confirm the pool/OS
  ZFS version.
- **No scheduled scrub** — intermittent box; scrubbing is best-effort/manual for
  now (candidate to fold into the on-connect workflow later).
- **`Type = "exec"` + internal retry loop** — the script only exits (non-zero)
  on its own crash; success ends in `poweroff`. Validate the "still failing"
  ntfy fires once at ~1h and that poweroff actually happens post-sync.
