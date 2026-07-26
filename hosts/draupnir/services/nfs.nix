{...}:
# NFSv4 export of the media library to asgard (the *arrs write imports here,
# Jellyfin reads them back). draupnir owns the storage; the media stack itself
# stays on asgard — see hosts/asgard/services/media/CLAUDE.md.
#
# Two datasets are exported:
#   - tank/media       → churny, *arr-managed, re-downloadable. NOT snapshotted.
#   - tank/essentials  → curated "keep-forever" films, snapshotted by sanoid and
#                        (later) replicable offsite. A film worth keeping is
#                        moved out of tank/media/library/movies into here by hand.
#
# gid contract: NFSv4 with sec=sys maps permissions NUMERICALLY. The arr users
# (sonarr, radarr, …) have asgard-side uids that don't exist on this box, so the
# shared `media` GROUP is what carries write/read access across the wire — its
# gid MUST match on both hosts. Pinned to 1500 here and in asgard storage.nix.
{
  users.groups.media.gid = 1500;

  # Library layout on the exported datasets, setgid 2775 so files the *arrs write
  # over NFS inherit group media(1500) and stay group-readable for Jellyfin
  # (also in `media` on asgard).
  #
  # NOT via systemd.tmpfiles.rules: tmpfiles-setup can run *before* the ZFS
  # legacy mounts (tank/media, tank/essentials) are active during a
  # `nixos-rebuild switch`, so it creates these dirs on the underlying root where
  # the later mount shadows them — the datasets end up empty with default perms.
  # This oneshot is ordered after the mounts (RequiresMountsFor) and before nfsd,
  # so the exported tree always has the setgid layout. Idempotent.
  systemd.services.media-library-layout = {
    description = "setgid library layout on tank/media + tank/essentials";
    wantedBy = ["multi-user.target"];
    before = ["nfs-server.service"];
    unitConfig.RequiresMountsFor = ["/tank/media" "/tank/essentials"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      mkdir -p /tank/media/library/{series,movies,music}
      chgrp media /tank/media/library /tank/media/library/{series,movies,music} /tank/essentials
      chmod 2775 /tank/media/library /tank/media/library/{series,movies,music} /tank/essentials
    '';
  };

  services.nfs.server = {
    enable = true;
    # NFSv4-only, exported to asgard's LAN IP alone. The export ACL is the real
    # access gate; the single firewall hole below is coarse (2049 is all NFSv4
    # needs — no rpcbind/mountd ports). root_squash stays on: the arrs write as
    # their own uids, never root, so there's no reason to grant remote root.
    exports = ''
      /tank/media      192.168.1.54(rw,sync,no_subtree_check,root_squash)
      /tank/essentials 192.168.1.54(rw,sync,no_subtree_check,root_squash)
    '';
  };

  networking.firewall.allowedTCPPorts = [2049];
}
