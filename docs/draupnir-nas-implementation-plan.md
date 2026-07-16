# draupnir (UGREEN DXP4800 Plus) — NAS implementation plan

Status: **planned** (research done 2026-07-15; install pending explicit go).

## Goal

Bring up `draupnir`, a bare-metal NAS host, as the storage backend the rest of
the fleet already anticipates: `/mnt/nas/media` + `/mnt/nas/immich` on asgard
(currently TEMP(no-nas) tmpfiles stubs) and the restic offsite target for the
finance stack. 4× 1 TB SATA drives, tolerate one drive failure, ~3 TB usable.

## Hardware facts

- UGREEN NASync DXP4800 Plus: Intel Pentium Gold 8505 (5C/6T), 8 GiB DDR5,
  2.5GbE (`enp1s0`, currently the active NIC at 1000 Mbps) + 10GbE (unused).
- OS disk: 128 GB NVMe `nvme0n1` (YSO128GTLCW). Ships with UGOS — **full-disk
  backup verified 2026-07-15** on midgard (`~/backups/ugos-nvme0n1-2026-07-15.img.zst`
  + sha256 + layout notes; persisted via `/persist` since 2026-07-15). NixOS
  overwrites this disk; rollback = restore image. Note: the image was taken
  *after* enabling root SSH (lykill key + sshd drop-in), so a restored UGOS
  comes back remotely accessible.
- Data bays: 4× 1 TB SATA, old disks, nothing to preserve.
- Disk serials (`/dev/disk/by-id/`, captured 2026-07-15 — sdX letters shuffle
  between boots, always use these):
  - `nvme-YSO128GTLCW-E3C-2_511250514278001307` (OS disk)
  - `ata-ST1000DM003-1ER162_S4Y4DKY7`
  - `ata-ST1000DM003-1CH162_Z1D5SVVC`
  - `ata-ST1000DM010-2EP102_ZN18KFTT`
  - `ata-TOSHIBA_DT01ACA100_Z241JNARS`
- BIOS: **watchdog already disabled** (mandatory — otherwise the BIOS reboots
  any non-UGOS OS). Ctrl+F12 did NOT work for BIOS entry on this unit; direct
  HDMI (no adapters) + USB keyboard required. TODO: record the key that worked.
- Caution: one unexplained reboot on 2026-07-15 while swapping the ethernet
  cable (possibly a power nudge). If spontaneous reboots recur under NixOS,
  re-check the BIOS watchdog first.
- Fan chip: ITE IT8613E, not in mainline `it87`. Needs the out-of-tree
  frankcrawford/it87 module with `force_id=0x8613 ignore_resource_conflict=1`
  plus `acpi_enforce_resources=lax` (see daskladas/nasdots for a working
  NixOS derivation for this exact box).
- Current DHCP lease: `192.168.1.39`. Target static IP: `192.168.1.56`
  (continues the asgard `.54` / bifrost `.55` sequence).

## Decision record: storage layout

**Chosen: ZFS raidz1 across the 4 SATA drives** (~2.7 TiB usable after
overhead). OS stays on the NVMe with the standard `btrfs-disk-uefi.nix`
layout (btrfs for OS + ZFS for data coexist fine).

Alternatives considered and rejected:

- **btrfs native RAID5** — write hole still unfixed; upstream still marks
  RAID5/6 not-for-production (2026). Off the table despite the repo being
  btrfs-everywhere; all existing layouts are single-disk.
- **SnapRAID + mergerfs (notthebee's `emily`)** — 3× XFS data + 1 parity +
  ZFS SSD cache + unRAID-style mover. Same 3/4 capacity, but parity is
  computed on a nightly timer (new files unprotected until the next sync),
  no self-healing on read, and it needs two mergerfs layers + a custom mover.
  Its advantages (mixed drive sizes, per-drive spin-down, partial survival
  of a 2-drive loss) fit huge re-downloadable media hoards — not this NAS,
  which will hold Immich photo originals and finance backup repos.
- **mdadm RAID5 + btrfs on top (daskladas/nasdots)** — proven on this exact
  hardware, but btrfs-over-md detects corruption without being able to
  self-heal it, and mdadm has its own write-hole/journal considerations.
  raidz1 gives checksums + parity in one layer.

Why raidz1 fits: real-time parity (no unprotected window), checksums with
self-healing on scrub/read, snapshots (cheap oops/ransomware protection for
photos), `zfs send` as a future backup channel, and single-disk raidz
expansion is GA since OpenZFS 2.3 if a bigger bay/drive era comes. First-class
NixOS support: disko declares the pool, `services.zfs.autoScrub` handles
integrity, ZED handles alerting.

ZFS notes for this box:
- `networking.hostId` is mandatory (8 hex chars, e.g. from
  `head -c8 /etc/machine-id`).
- Keep the **default NixOS kernel** (ZFS lags bleeding-edge kernels; no
  xanmod here).
- 8 GiB RAM is fine; ARC defaults to 50% (4 GiB). Optionally cap with
  `boot.kernelParams = ["zfs.zfs_arc_max=3221225472"]` if services need room.
- No ECC — accepted; checksums+scrubs still catch disk-side rot.

Pool/dataset sketch (all via disko, `mountpoint=legacy` + `fileSystems`):

```
zpool tank  (raidz1, 4× 1TB by-id, ashift=12, autotrim=off)
  compression=zstd  atime=off  xattr=sa  acltype=posixacl  normalization=formD
  tank/media    → /tank/media    recordsize=1M   (Jellyfin library)
  tank/immich   → /tank/immich   recordsize=1M   (photo originals; auto-snapshots ON)
  tank/backups  → /tank/backups  recordsize=1M   (restic repo, finance offsite plan)
```

## Phases

### Phase 0 — burn-in the old drives (before trusting them) — DONE 2026-07-16
**Result: all 4 passed.** Extended tests "Completed without error"; Reallocated /
Pending / Offline_Uncorrectable all 0 before and after (baselines + post-test
dumps in midgard `~/backups/smart-{baseline,post}-*.txt`). Power-on hours at
test time: 34.7k (ST1000DM003-1CH162), 3.5k (ST1000DM003-1ER162), 601
(Toshiba), 6 (ST1000DM010). The 34.7k-hour drive is the statistical weak link —
fine for raidz1, but it's the first candidate when a drive eventually gets
swapped.

`smartctl -t long` on all 4 SATA disks (in parallel; ~2–3 h for 1 TB), review
reallocated/pending sectors; optionally a `badblocks -sv` pass. These are old
1 TB disks — raidz1 only survives one failure, so don't build on a dying drive.
As of 2026-07-15 the box is already sitting in the kexec'd RAM installer and
it ships both `smartctl` and `badblocks` — Phase 0 can run there directly
(a power-cycle back to UGOS loses nothing; the tests live on the drives).
Serials already recorded in Hardware facts above.

### Phase 1 — scaffold `hosts/draupnir/` (no hardware touched)
1. Pre-generate the SSH host key locally (`ssh-keygen -t ed25519`), commit
   `hosts/draupnir/ssh_host_ed25519_key.pub`, add the derived age recipient
   `&draupnir` to `.sops.yaml`, run `sops updatekeys hosts/common/secrets.yaml`.
   The private key is injected at install via `nixos-anywhere --extra-files`
   (never committed) — this avoids the impermanence-era host-key chicken-and-egg.
2. `hosts/draupnir/default.nix`: mirror asgard's shape — core, users,
   `../optional/tailscale.nix`, static IP `192.168.1.56` + AdGuard nameserver
   + Quad9 fallback, systemd-boot, `btrfs-disk-uefi.nix` with
   `device = "/dev/disk/by-id/nvme-YSO128GTLCW-…"` (by-id, NOT /dev/nvme0n1).
3. `hosts/draupnir/disko-data.nix`: the raidz1 zpool + datasets above
   (host-local for now; promote to `hosts/common/disks/` if a second ZFS
   host ever appears).
4. ZFS plumbing: `networking.hostId`, `boot.supportedFilesystems = ["zfs"]`,
   `services.zfs.autoScrub.enable = true` (monthly is plenty for 4 spinners).
5. Fan control module (it87 derivation + modprobe options, from nasdots).
6. `flake.nix`: add `nixosConfigurations.draupnir`.
7. Validate: `nix eval .#nixosConfigurations.draupnir.config.system.build.toplevel.drvPath`.

### Phase 2 — install (DESTRUCTIVE: wipes UGOS NVMe — needs explicit go)
Path already prepared in the previous session: UGOS has root SSH enabled
(lykill key), kexec works. From midgard:

```bash
nixos-anywhere --phases kexec,disko,install,reboot \
  --extra-files ~/backups/draupnir-install \
  --disk-encryption-keys /tmp/tank.key ~/backups/draupnir-install/persist/tank.key \
  --flake .#draupnir --target-host root@192.168.1.39
```

Notes: if the box is still in the kexec'd installer from the backup session,
nixos-anywhere detects that and skips the kexec phase (harmless to list it);
if it was power-cycled back to UGOS, the kexec path re-runs from there. The
host key in the `--extra-files` dir must be mode 0600 (permissions are
preserved into the installed system).

Encryption: `tank` uses native ZFS encryption (aes-256-gcm, hex keyfile).
`--disk-encryption-keys` places the key at `/tmp/tank.key` in the installer so
`zpool create` can consume it; `--extra-files` ships the same key to
`/persist/tank.key` in the installed system, where the pool's `keylocation`
points (reset by disko's `postCreateHook`). The key is backed up in sops
(`hosts/draupnir/secrets.yaml`, `tank-encryption-key`) and on midgard at
`~/backups/draupnir-install/persist/tank.key` — if every copy is lost, the
pool is gone.

Post-boot: confirm tailscale enrollment (`100.64.0.4` expected by order),
`zpool status` clean, scrub timer armed, fans behaving.

### Phase 3 — NFS exports + shared GID contract
1. Pin `users.groups.media.gid = 1500;` on **both** draupnir and asgard
   (asgard's `storage.nix` checklist item — its `media` group is currently
   auto-allocated). Same for an `immich` uid/gid pair if Immich stays
   uid-sensitive over NFS.
2. draupnir: `services.nfs.server.enable = true;` NFSv4-only exports of
   `/tank/media` (rw, asgard only), `/tank/immich` (rw, asgard only),
   `/tank/backups` (rw, asgard only). Firewall: open 2049/tcp only.
3. AdGuard rewrite on bifrost: `draupnir.lan.valgrindr.net → 192.168.1.56`
   (needed for the mount device names + any future web UI; deploy bifrost).

### Phase 4 — asgard cutover (order matters: migrate before mounting)
1. **Migrate existing pre-NAS data first**: rsync asgard's current
   `/mnt/nas/media/library` and `/mnt/nas/immich` contents to the NFS
   exports (mount them temporarily at a staging path), preserving ownership.
2. Uncomment the `fileSystems."/mnt/nas/media"` block in
   `hosts/asgard/services/media/storage.nix` (device
   `draupnir.lan.valgrindr.net:/tank/media`, options `nofail`,
   `x-systemd.automount`, `_netdev`), add the equivalent for
   `/mnt/nas/immich`; remove the TEMP(no-nas) tmpfiles lines in
   `storage.nix` and `immich.nix`.
3. Stop media services + Immich during the flip; verify Sonarr/Radarr and
   Immich can write through the mounts, Jellyfin sees the library.
4. Update `hosts/asgard/CLAUDE.md` + `hosts/asgard/services/media/CLAUDE.md`
   (pre-NAS caveats are now stale) and create `hosts/draupnir/CLAUDE.md`.

### Phase 5 — data-protection plumbing
1. `services.sanoid` (or `services.zfs.autoSnapshot`) on `tank/immich`
   (e.g. 24 hourlies / 30 dailies / 6 monthlies) — snapshots are not backup
   but cover fat-fingers instantly.
2. Finance offsite plan (docs/memory: pg_dump 7d local + restic 90d to NAS)
   now has its target: restic repo on `/tank/backups`.
3. `services.smartd` with long self-tests weekly (notthebee's schedule is a
   good template). ZED alerting: no mail infra on the fleet — leave ZED
   default (journal) and add a TODO for ntfy/Telegram push; check
   `zpool status` in the meantime.

## Deferred / out of scope

- 10GbE NIC (needs a switch that can use it).
- Samba shares for non-NixOS clients (NFS covers asgard; add later if a
  laptop/TV needs SMB).
- Immich originals served read-only to Jellyfin or other consumers.
- raidz expansion to bigger drives (supported: replace-one-at-a-time with
  autoexpand, or `zpool attach` a 5th disk if a bay frees up).

## Sources

- notthebee/nix-config (`emily` host): https://git.notthebe.ee/notthebee/nix-config
- daskladas/nasdots (NixOS on DXP4800 Plus): https://github.com/daskladas/nasdots
- Debian wiki, UGREEN NASync install notes: https://wiki.debian.org/InstallingDebianOn/Ugreen
- btrfs RAID5/6 status: https://btrfs.readthedocs.io/en/latest/Status.html
- NixOS wiki, ZFS: https://wiki.nixos.org/wiki/ZFS
- OpenZFS raidz expansion (GA in 2.3): https://freebsdfoundation.org/blog/openzfs-raid-z-expansion-a-new-era-in-storage-flexibility/
- NixOS Discourse, mergerfs+SnapRAID discussion: https://discourse.nixos.org/t/feedback-and-advice-on-setting-up-mergerfs-snapraid-in-nixos/58290
