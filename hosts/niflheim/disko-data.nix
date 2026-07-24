# Backup pool: one big HDD, no redundancy. This is copy #3 in a 3-2-1 scheme
# and is fully reconstructible from draupnir via raw `zfs send`, so a single
# disk is an accepted trade: ZFS checksums still DETECT bit-rot, but with no
# second copy there's nothing to self-heal from, and a whole-disk failure just
# means "replace it and re-seed on LAN". See docs/immich-offsite-backup-plan.md
# §3.
#
# The pool is UNENCRYPTED on purpose. It only ever holds datasets raw-received
# (`syncoid --sendoptions=w`) from draupnir; those arrive already encrypted
# under tank's key and stay ciphertext at rest. niflheim never holds that key —
# that's the whole point (§5). Received datasets become their own encryption
# roots inside this plain pool.
#
# TODO(hw): replace the by-id path once the box exists (`ls -l /dev/disk/by-id`).
{
  disko.devices = {
    disk.cold = {
      type = "disk";
      device = "/dev/disk/by-id/REPLACE-ME-cold-hdd"; # TODO(hw)
      content = {
        type = "gpt";
        partitions.zfs = {
          size = "100%";
          content = {
            type = "zfs";
            pool = "cold";
          };
        };
      };
    };

    zpool.cold = {
      type = "zpool";
      # Single-disk vdev — a lone disk, not a mirror/raidz, so no `mode`.
      mode = "";
      options = {
        ashift = "12";
        autotrim = "off"; # spinner
      };
      # Pool-wide defaults. NO `encryption` here — received datasets bring their
      # own encryption (raw send), and the pool itself must stay a plain,
      # valid receive target.
      rootFsOptions = {
        compression = "zstd";
        atime = "off";
        xattr = "sa";
        acltype = "posixacl";
        normalization = "formD";
        mountpoint = "none";
      };
      # No child datasets declared on purpose: `cold/immich` is created by the
      # first `zfs receive` (syncoid). Pre-creating it would collide with the
      # raw-received encryption root.
    };
  };
}
