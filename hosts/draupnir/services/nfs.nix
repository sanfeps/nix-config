{...}:
# NFSv4 export of the media library to asgard (the *arrs write imports here,
# Jellyfin reads them back). draupnir owns the storage; the media stack itself
# stays on asgard — see hosts/asgard/services/media/CLAUDE.md.
#
# qBittorrent (on asgard) also *downloads* here now, into tank/media/downloads —
# offloaded off asgard's small local disk so concurrent downloads can't fill it
# and freeze the Proxmox VM. See the media-library-layout script below.
#
# Three datasets are exported:
#   - tank/media       → churny, *arr-managed, re-downloadable. NOT snapshotted.
#   - tank/essentials  → curated "keep-forever" films, snapshotted by sanoid and
#                        (later) replicable offsite. A film worth keeping is
#                        moved out of tank/media/library/movies into here by hand.
#   - tank/appdata     → app-state backups pushed by asgard (Yamtrack CSV export
#                        + pg_dump). Snapshotted AND queued for the niflheim
#                        offsite. Different access model from the two above —
#                        see the squash note on users.users.appdata below.
#
# gid contract: NFSv4 with sec=sys maps permissions NUMERICALLY. The arr users
# (sonarr, radarr, …) have asgard-side uids that don't exist on this box, so the
# shared `media` GROUP is what carries write/read access across the wire — its
# gid MUST match on both hosts. Pinned to 1500 here and in asgard storage.nix.
{
  users.groups.media.gid = 1500;

  # Identity that asgard's root-run appdata-nas-sync unit lands as on this box.
  # The export below keeps root_squash (no remote root, same as the media
  # exports) but pins the squash target to this uid/gid instead of the default
  # nobody/65534 — so a root unit on asgard can write the backups without ever
  # holding root here, and the files land owned by a real, named account.
  # Numeric, because NFSv4 sec=sys maps permissions by number.
  users.groups.appdata.gid = 1501;
  users.users.appdata = {
    isSystemUser = true;
    group = "appdata";
    uid = 1501;
    description = "Owner of app-state backups pushed from asgard (tank/appdata)";
  };

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
    description = "setgid library layout on tank/media + tank/essentials + tank/appdata";
    wantedBy = ["multi-user.target"];
    before = ["nfs-server.service"];
    unitConfig.RequiresMountsFor = ["/tank/media" "/tank/essentials" "/tank/appdata"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      mkdir -p /tank/media/library/{series,movies,music}
      # Download staging: qBittorrent on asgard writes here over NFS instead of
      # its local disk (see hosts/asgard/services/media/qbittorrent.nix — keeps
      # asgard's disk + the Proxmox thin-pool from filling on concurrent
      # downloads). A plain SUBDIRECTORY of tank/media (not a child dataset) so
      # the *arr `Move` import into .../library is a same-filesystem atomic
      # rename, not a copy. setgid media(1500) so qBit's writes and the *arrs'
      # reads/moves share the group.
      mkdir -p /tank/media/downloads/.incomplete
      chgrp media /tank/media/library /tank/media/library/{series,movies,music} /tank/media/downloads /tank/media/downloads/.incomplete /tank/essentials
      chmod 2775 /tank/media/library /tank/media/library/{series,movies,music} /tank/media/downloads /tank/media/downloads/.incomplete /tank/essentials

      # App-state backups (asgard → NFS). Owned by the squash identity the
      # export pins below, 0750: unlike the media tree this is NOT shared with
      # a group of local services, so nothing outside root/appdata needs in.
      mkdir -p /tank/appdata
      chown appdata:appdata /tank/appdata
      chmod 0750 /tank/appdata
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
      /tank/appdata    192.168.1.54(rw,sync,no_subtree_check,root_squash,anonuid=1501,anongid=1501)
    '';
  };

  networking.firewall.allowedTCPPorts = [2049];
}
