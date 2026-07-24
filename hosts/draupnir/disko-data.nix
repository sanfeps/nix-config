# Data pool: raidz1 across the 4x 1 TB SATA bays (~2.7 TiB usable).
# Decision record + rejected alternatives (btrfs RAID5, SnapRAID+mergerfs,
# mdadm+btrfs): docs/draupnir-nas-implementation-plan.md.
#
# All 4 drives passed SMART extended tests 2026-07-16 (Phase 0). Serials are
# load-bearing: sdX letters shuffle between boots, by-id is stable.
{
  disko.devices = {
    disk = let
      zfsBay = device: {
        type = "disk";
        inherit device;
        content = {
          type = "gpt";
          partitions.zfs = {
            size = "100%";
            content = {
              type = "zfs";
              pool = "tank";
            };
          };
        };
      };
    in {
      bay1 = zfsBay "/dev/disk/by-id/ata-ST1000DM003-1ER162_S4Y4DKY7";
      bay2 = zfsBay "/dev/disk/by-id/ata-ST1000DM003-1CH162_Z1D5SVVC";
      bay3 = zfsBay "/dev/disk/by-id/ata-ST1000DM010-2EP102_ZN18KFTT";
      bay4 = zfsBay "/dev/disk/by-id/ata-TOSHIBA_DT01ACA100_Z241JNARS";
    };

    zpool.tank = {
      type = "zpool";
      mode = "raidz1";
      options = {
        ashift = "12";
        autotrim = "off"; # spinners
      };
      # Pool-wide defaults, inherited by every dataset.
      rootFsOptions = {
        compression = "zstd";
        atime = "off";
        xattr = "sa";
        acltype = "posixacl";
        normalization = "formD";
        mountpoint = "none";
        # Native ZFS encryption on the pool root, inherited by all datasets.
        # Threat model: drives that leave the box (RMA, disposal, single-bay
        # theft) — NOT whole-box theft; the key lives in plaintext on the OS
        # NVMe so the pool auto-unlocks at boot (zfs-import-tank loads file://
        # keys; /persist is neededForBoot). Backups of the key: sops
        # (hosts/draupnir/secrets.yaml, tank-encryption-key) and midgard
        # ~/backups/draupnir-install/persist/tank.key. Losing every copy of
        # the key means losing the pool.
        encryption = "aes-256-gcm";
        keyformat = "hex";
        # Creation-time location: nixos-anywhere --disk-encryption-keys drops
        # the key here in the installer before the disko phase runs.
        keylocation = "file:///tmp/tank.key";
      };
      # The runtime key is shipped to /persist/tank.key via --extra-files;
      # point the pool there for every import after the install.
      postCreateHook = ''
        zfs set keylocation="file:///persist/tank.key" tank
      '';
      datasets = {
        # Jellyfin library (served to asgard over NFS).
        media = {
          type = "zfs_fs";
          mountpoint = "/tank/media";
          options = {
            mountpoint = "legacy";
            recordsize = "1M";
          };
        };
        # Immich photo/video originals — the irreplaceable data on this box.
        # Sanoid auto-snapshots planned (Phase 5).
        immich = {
          type = "zfs_fs";
          mountpoint = "/tank/immich";
          options = {
            mountpoint = "legacy";
            recordsize = "1M";
          };
        };
        # NOTE: a `tank/backups` dataset (finance restic offsite target) was
        # removed 2026-07-24 for simplicity — nothing wrote to it yet. Re-add it
        # here (plus its offsite legs) when the finance offsite plan is built.
      };
    };
  };
}
