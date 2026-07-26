# draupnir

NAS host. Bare-metal UGREEN NASync DXP4800 Plus (Pentium Gold 8505, 8 GiB DDR5).
Full lifecycle doc: `docs/draupnir-nas-implementation-plan.md` (decision record,
phases, UGOS rollback procedure).

- LAN IP: `192.168.1.56` (static-at-OS on `enp1s0`, the 2.5GbE port; the 10GbE
  port is unused). Tailnet member via `hosts/optional/tailscale.nix`.
- OS: 128 GB NVMe with `btrfs-disk-uefi.nix` (plain BTRFS, no wipe-on-boot, no
  LUKS). The NVMe previously held UGOS — a verified full-disk image lives on
  midgard at `~/backups/ugos-nvme0n1-2026-07-15.img.zst` (+ sha256 + layout
  notes) if factory rollback is ever needed.
- Data: ZFS **raidz1** pool `tank` over the 4x 1 TB SATA bays (~2.7 TiB usable),
  declared in `disko-data.nix`. Datasets: `tank/media`, `tank/immich`,
  `tank/essentials` → mounted at `/tank/*` (legacy mountpoints via fileSystems).
  `tank/essentials` was `zfs create`d by hand (disko only formats at install).
  `networking.hostId` is load-bearing for pool import — never change it.
- Encryption: native ZFS (aes-256-gcm) on the pool root, inherited by all
  datasets. Key is a plaintext hex file at `/persist/tank.key` (auto-unlock at
  boot; threat model is drives leaving the box, not whole-box theft). Key
  backups: sops `hosts/draupnir/secrets.yaml` (`tank-encryption-key`) and
  midgard `~/backups/draupnir-install/persist/tank.key`. **Never lose all
  copies — the pool is unrecoverable without the key.** A replacement NVMe
  needs the key restored to `/persist/tank.key` before `tank` will import
  with keys loaded.
- Kernel: **default NixOS kernel only** (ZFS compatibility; no xanmod).
- Fans: ITE IT8613E needs the out-of-tree it87 fork (`fan-control.nix` +
  `it87.nix`, `force_id=0x8613` + `acpi_enforce_resources=lax`). Calibrated
  2026-07-16: pwm2→fan2 (CPU fan), pwm3→fan3 (case fan), pwm4/5 unused. The
  `fan-curve` systemd service drives them (CPU temp → pwm2, hottest drivetemp
  → pwm3); it deliberately avoids `hardware.fancontrol` because drivetemp
  hwmon paths shuffle with SATA enumeration. On service stop the chip falls
  back to its own auto mode.
- BIOS: hardware watchdog must stay **disabled** or non-UGOS OSes get rebooted.
  If the box starts rebooting spontaneously, check that setting first.
- Alerting: ZED pushes pool events (degraded/faulted, errors, scrub/resilver)
  to the self-hosted ntfy on bifrost, topic `zfs-draupnir` (config inline in
  `default.nix`, ZFS section). `ZED_NOTIFY_VERBOSE=1` so the monthly
  `scrub_finish` push doubles as a pipeline heartbeat — if scrub notifications
  stop arriving, the alerting itself is broken. The publish token is read at
  event time via `$(cat /run/secrets/zed-ntfy-token)` (sops); zed.rc renders
  settings unescaped and zedlets source it as root, so nothing lands in the
  store. Same token value lives in bifrost's `ntfy/auth-env`.

## Services

Wired in `services/default.nix`:

- **`caddy.nix`** — draupnir's own Caddy via the shared `services.caddyNjalla`
  module (wildcard LE cert for `*.lan.valgrindr.net`, Njalla DNS-01, same
  per-host-ingress pattern as asgard/bifrost). `default_bind 192.168.1.56`
  pins every vhost to the LAN IP.
- **`immich.nix`** — Immich via the reusable `homelab.services.immich` module.
  Fresh install (the asgard instance was empty scaffold — cutover runbook:
  `docs/immich-draupnir-migration-runbook.md`); the library lives directly on
  the dataset at `/tank/immich`. Binds `127.0.0.1:2283`, fronted by the local
  Caddy at `https://immich.lan.valgrindr.net`; AdGuard on bifrost answers
  `192.168.1.56` for that name. **System settings are declarative**
  (`services.immich.settings` → IMMICH_CONFIG_FILE): the admin System
  Settings UI is read-only, changes go through Nix. Declared: nightly DB
  dumps to `<mediaLocation>/backups`, storage template (`{{y}}/{{MM}}`),
  ML toggles, per-queue job concurrency caps (8 GiB box), trash 30d.
  Don't set `machineLearning.urls` — its default comes from the env var the
  NixOS module wires to the local ML service.

RAM note: 8 GiB total, shared with the ZFS ARC — capped at 3 GiB via
`zfs.zfs_arc_max` in `default.nix`. If Immich ML jobs still cause memory
pressure, `homelab.services.immich.machineLearning = false` is the next lever.

- **`nfs.nix`** — NFSv4 export of `tank/media` (arr library) + `tank/essentials`
  (curated keep-set) to **asgard only** (`192.168.1.54` in the export ACL). The
  media stack stays on asgard; this box just serves the bytes. Pins
  `users.groups.media.gid = 1500` (the numeric cross-host contract — asgard's
  `media` group matches) and owns the setgid `2775` library tree
  (`/tank/media/library/{series,movies,music}`). Only firewall hole: TCP 2049.
- **`sanoid.nix`** — automatic ZFS snapshots of `tank/immich` **and
  `tank/essentials`** (24h / 30d / 12m / **3y** via the `irreplaceable`
  template; the 3 yearlies exist so the offsite copy can *receive* them —
  offsite plan §4). `tank/media` is deliberately NOT snapshotted (churny +
  re-downloadable; rationale in the file header). Recover files from
  `/tank/<ds>/.zfs/snapshot/<name>/`.
- **`syncoid-source.nix`** — makes draupnir a **send-only** replication source
  for the offsite box (niflheim). A dedicated `syncoid` user has
  `send,snapshot,bookmark,mount` delegated on `tank/immich` (no
  `destroy`/`receive`/`hold`); niflheim *pulls*. **INERT** until niflheim's
  pubkey is added to `openssh.authorizedKeys.keys`. Design:
  `docs/immich-offsite-backup-plan.md`.

### Adding a new dataset to the offsite replica

Offsite replication (to niflheim) is **additive but multi-file — and has a
non-obvious prerequisite**. To replicate a new `tank/<name>` (e.g. `tank/repos`):

1. **Snapshot the source** — `hosts/draupnir/services/sanoid.nix`. syncoid pulls
   with `--no-sync-snap`, so it can only send snapshots that **already exist**. A
   dataset with no sanoid policy has *nothing to send* and its leg silently does
   nothing. Give it a template (`irreplaceable` for photo-like data; a lighter
   one for churny repos).
2. **Delegate** — add `"tank/<name>"` to the `datasets` list in
   `hosts/draupnir/services/syncoid-source.nix`.
3. **niflheim pull** — add `{ src = "tank/<name>"; dst = "cold/<name>"; }` to
   `hosts/niflheim/services/syncoid.nix`.
4. **niflheim prune** — add `datasets."cold/<name>".useTemplate = ["offsite"];`
   to `hosts/niflheim/services/sanoid.nix`, or the copy grows unbounded.

Each is a one-liner; other datasets' legs are untouched. **Removing** a dataset
is the only sticky bit: `zfs allow` persists in the pool, so drop it from the
list *and* `zfs unallow syncoid … tank/<name>` by hand.

> The finance-stack offsite (a `tank/backups` restic target) is **deferred** —
> that dataset was removed 2026-07-24 (nothing wrote to it). When it's built,
> it'll need step 1 (a snapshot policy) too: syncoid `--no-sync-snap` can only
> ship existing snapshots, and a light policy keeps the no-`destroy` delegation
> (dropping `--no-sync-snap` would force granting `destroy`, which we reject).

## Roles

- **NFSv4 export of `/tank/media` + `/tank/essentials` to asgard only** — DONE
  (`services/nfs.nix`). gid contract: `media` gid 1500 pinned on both hosts.
  `tank/immich` is not exported — Immich runs locally. (`tank/backups` export
  returns with the finance offsite.)
- Finance-stack offsite (a restic `tank/backups` target) is **deferred** — the
  reserved dataset was removed 2026-07-24; re-add when it's built. Offsite
  replication of `tank/immich` is **decided and in progress**: syncoid raw-send
  (pull) to a
  dedicated intermittent ZFS box, niflheim, over the tailnet. Source side
  (`syncoid-source.nix`) is deployed; niflheim host is scaffolded but awaits
  hardware. See `docs/immich-offsite-backup-plan.md` + `hosts/niflheim/CLAUDE.md`.
- Monthly `services.zfs.autoScrub` (active); smartd (pending).

## Install / recovery

Installed via nixos-anywhere (kexec from UGOS or any live env; the box is
UEFI). Host SSH key was pre-generated (age recipient `&draupnir` in
`.sops.yaml`); private key is injected with `--extra-files` from midgard
`~/backups/draupnir-install/` — never committed. Deploys after install follow
the asgard pattern (`--target-host`/`--build-host sanfe@192.168.1.56`).
