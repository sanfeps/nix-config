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
  `tank/backups` → mounted at `/tank/*` (legacy mountpoints via fileSystems).
  `networking.hostId` is load-bearing for pool import — never change it.
- Kernel: **default NixOS kernel only** (ZFS compatibility; no xanmod).
- Fans: ITE IT8613E needs the out-of-tree it87 fork (`fan-control.nix` +
  `it87.nix`, `force_id=0x8613` + `acpi_enforce_resources=lax`). Driver loads;
  a fancontrol curve is TODO pending on-box `pwmconfig` calibration.
- BIOS: hardware watchdog must stay **disabled** or non-UGOS OSes get rebooted.
  If the box starts rebooting spontaneously, check that setting first.

## Roles (planned, see plan doc Phases 3–5)

- NFSv4 exports of `/tank/{media,immich,backups}` to asgard only (gid contract:
  `media` gid 1500 pinned on both hosts).
- Restic offsite target for the finance stack.
- Sanoid snapshots on `tank/immich`; monthly `services.zfs.autoScrub`; smartd.

## Install / recovery

Installed via nixos-anywhere (kexec from UGOS or any live env; the box is
UEFI). Host SSH key was pre-generated (age recipient `&draupnir` in
`.sops.yaml`); private key is injected with `--extra-files` from midgard
`~/backups/draupnir-install/` — never committed. Deploys after install follow
the asgard pattern (`--target-host`/`--build-host sanfe@192.168.1.56`).
