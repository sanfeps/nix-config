# draupnir disk failure runbook

`tank` is raidz1 over 4× 1 TB SATA (bays 1–4, by-id serials in
`hosts/draupnir/disko-data.nix`). raidz1 survives **one** disk failure; during
any resilver there is **zero** redundancy. The pool is encrypted (native ZFS
aes-256-gcm) — see the "How encryption interacts" section; the short version
is that it changes nothing about disk replacement and everything about OS-disk
recovery.

## Detection

- Manual: `zpool status -x` (prints "all pools are healthy" or the problem).
- `zpool status tank` shows the failed/offlined member as `OFFLINE`,
  `FAULTED`, `REMOVED`, or `UNAVAIL`, and the pool as `DEGRADED`.
- `zfs-zed` runs by default and journals every event in real time
  (`journalctl -u zfs-zed`: `statechange`, `vdev_attach`,
  `resilver_start/finish` — all confirmed during the drill).
- **Push alerts are wired and validated (2026-07-19)**: ZED publishes every
  notify-worthy event (state changes, errors, scrub/resilver finish) to the
  self-hosted ntfy on bifrost, topic `zfs-draupnir`
  (`https://ntfy.lan.valgrindr.net`, login `sanfe`). Config lives in
  `hosts/draupnir/default.nix` (ZFS section); server in
  `hosts/bifrost/services/ntfy.nix`. `ZED_NOTIFY_VERBOSE=1`, so the
  **monthly `scrub_finish` push doubles as a heartbeat** — if a month passes
  without a scrub notification, the alerting pipeline itself is broken: check
  `systemctl status ntfy-sh` on bifrost, `journalctl -u zfs-zed` on draupnir,
  and `curl https://ntfy.lan.valgrindr.net/v1/health`. Repeated events are
  rate-limited to one per hour (`ZED_NOTIFY_INTERVAL_SECS=3600`).

A degraded pool keeps serving all data (reconstructed from parity), with
reduced read performance. Services stay up. Do not panic; do replace promptly.

## Scenario A — one data drive fails (the expected case)

Verified end-to-end with a live drill on the empty pool, 2026-07-16 (see
"Drill log" at the bottom). ~10 min hands-on plus resilver time.

1. Identify the dead member: `zpool status tank`. **The pool names its
   members by their `wwn-*` aliases**, not the `ata-<model>_<serial>` names
   used in `hosts/draupnir/disko-data.nix` — map between them with
   `readlink -f /dev/disk/by-id/...` (both alias the same `/dev/sdX`), then
   serial → physical bay via disko-data.nix (bay1–bay4, declared top to
   bottom). Drill-observed mapping for bay1:
   `ata-ST1000DM003-1ER162_S4Y4DKY7` = `wwn-0x5000c5008c402114`.
2. If the drive is dying-but-present, offline it first:
   `sudo zpool offline tank <by-id>-part1`.
3. Swap the physical drive (power off first if unsure about hotplug; the
   DXP4800+ bays are hot-swap capable but a planned shutdown is free).
4. Find the new drive's by-id: `ls -l /dev/disk/by-id/ | grep -v part`.
5. Replace, giving ZFS the **whole disk** (it partitions it itself):

   ```bash
   sudo zpool replace tank <old-by-id>-part1 /dev/disk/by-id/<new-by-id>
   ```

6. Watch the resilver: `zpool status tank` (shows progress + ETA). Pool
   returns to `ONLINE` when done. Run a scrub afterwards for peace of mind:
   `sudo zpool scrub tank`.
7. Housekeeping:
   - Update the dead serial in `hosts/draupnir/disko-data.nix` (documentation
     only — nothing re-executes) and commit.
   - Take a SMART baseline of the new drive (see
     `~/backups/smart-baseline-*.txt` on midgard for the format).
   - RMA/destroy the old drive **without wiping anxiety**: everything on it
     is aes-256-gcm ciphertext (this is exactly what the encryption is for).

### Upgrading to bigger drives (planned path, not a failure)

Same procedure as above, four times, one drive at a time, waiting for each
resilver to complete. Run `sudo zpool set autoexpand=on tank` once before
starting; the pool grows when the **last** drive is replaced. Scrub before
each swap — during every resilver the pool has no redundancy, and stale
parity discovered mid-resilver is how pools die.

## Scenario B — the OS NVMe fails

The pool is fine (it's on the bays), but the OS, the host SSH key, and — 
critically — **the pool's encryption key at `/persist/tank.key`** live on the
NVMe.

1. Get a replacement NVMe in the slot.
2. **Before reinstalling: physically disconnect / pull the 4 data bays, or
   comment out the `./disko-data.nix` import in `hosts/draupnir/default.nix`
   for the install run.** nixos-anywhere re-runs disko on *everything* the
   config declares — including `zpool create -f tank`, which would destroy
   the pool. Pulling the bays is the belt-and-suspenders option; do it.
3. Reinstall exactly like the first install (Phase 2 command in
   `docs/draupnir-nas-implementation-plan.md`): kexec/USB into an installer,
   `nixos-anywhere` with `--extra-files ~/backups/draupnir-install` (host SSH
   key + `persist/tank.key`) and `--disk-encryption-keys`. If the staging dir
   is gone, reconstruct it:
   - Host SSH key: cannot be recovered (private half only existed on the
     NVMe + midgard staging dir). Generate a new one, update
     `hosts/draupnir/ssh_host_ed25519_key.pub`, the `&draupnir` age recipient
     in `.sops.yaml`, and `sops updatekeys` both secrets files.
   - **tank.key: recover from sops** —
     `sops -d --extract '["tank-encryption-key"]' hosts/draupnir/secrets.yaml`
     (decryptable with your user age key). Write it to
     `persist/tank.key` in the staging dir, `chmod 400`, no trailing newline.
4. Boot the fresh OS, power down, reconnect the bays, boot again.
5. Import the pool: `sudo zpool import -f tank` (`-f` because the old OS
   never exported it). Confirm keys loaded + datasets mounted after a reboot
   (the import service handles it once `/persist/tank.key` is in place):
   `zfs get keystatus tank` → `available`.

## Scenario C — two or more drives die (pool lost)

raidz1 does not survive this. The pool is gone; recovery is restore-from-
backup. Current backup coverage:

- `tank/backups` (asgard finance restic target): originals live on asgard —
  nothing lost, re-point and re-seed.
- `tank/media`: re-acquirable by the *arr stack — annoying, not a disaster.
- `tank/immich`: **the irreplaceable one. As of 2026-07-16 there is no
  offsite copy — until an offsite replication/backup for tank/immich exists,
  a two-drive failure loses photos.** Sanoid snapshots (Phase 5) do NOT cover
  this (snapshots live in the same pool). Options when picking this up:
  `zfs send` to an offsite box, or restic from /tank/immich to cloud storage.

## How encryption interacts with all of this

- **Drive replacement / resilver: no interaction.** Resilvering copies raw
  (encrypted) blocks; it neither needs nor touches the key. `keystatus`
  stays `available` throughout — verified in the drill.
- **Failed/retired drives: no wiping needed.** Every block a bay drive ever
  held is ciphertext without `/persist/tank.key`. RMA freely.
- **The key is a single point of failure for the whole pool.** It exists in
  three places: `/persist/tank.key` (draupnir NVMe),
  `~/backups/draupnir-install/persist/tank.key` (midgard, `/persist`-backed),
  and `tank-encryption-key` in `hosts/draupnir/secrets.yaml` (sops, in git,
  decryptable by the user age key). Losing all three = losing the pool even
  with 4 healthy disks. Never "clean up" the sops copy.
- **OS reinstall requires the key** (Scenario B step 3) — the pool imports
  fine without it, but no dataset can be mounted/decrypted.

## Drill log (2026-07-16, empty pool)

Executed via `/tmp/failure-drill.sh` (staged from midgard) before any real
data landed on the pool:

1. Wrote 256 MiB of random data to `tank/media`, recorded sha256.
2. `zpool offline` on bay1 → pool `DEGRADED`, data still read back with
   correct checksum (served from parity), `keystatus` still `available`.
3. Wiped bay1's partition (wipefs + zeroing head/tail) to simulate a
   factory-new replacement drive.
4. `zpool replace tank <part> <part>` → resilver → pool `ONLINE`.
5. Checksum verified again; `zpool status -x` healthy; test data removed.

Results — all green:

- Degraded state entered and exited cleanly; test data read back with the
  correct checksum both while DEGRADED and after the resilver.
- Resilver: 86.9 MiB in **2 seconds** (only *allocated* data is resilvered —
  on full 1 TB drives expect **2–3 h** per swap instead).
- `keystatus` stayed `available` through every phase — encryption is
  invisible to the whole failure/replace path, as expected.
- `zfs-zed` journaled every transition in real time (eid `statechange
  OFFLINE` → `vdev_attach` → `resilver_start` → `resilver_finish`) — at drill
  time no notification went anywhere (journal only); the ZED→ntfy push
  channel closing that gap landed and was validated 2026-07-19 (see
  Detection).
- One deviation from the naive procedure, now folded into Scenario A: the
  pool knows its members by `wwn-*` names; `zpool offline` with the `ata-*`
  alias fails with "no such device in pool".
