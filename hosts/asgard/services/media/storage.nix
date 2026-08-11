{...}:
# Filesystem layout for the media stack.
#
# Everything lives on the NAS (draupnir's tank pool over NFSv4). asgard keeps
# NO media on its local disk — two concurrent big downloads used to fill
# /srv/media/downloads and freeze the VM into io-error via a full Proxmox
# thin-pool (see qbittorrent.nix). Three targets, all on draupnir:
#
#   - NAS (/mnt/nas/media/downloads): in-progress torrent data, a subdirectory
#     of the tank/media dataset (created setgid by draupnir's nfs.nix). Once an
#     *arr imports a release into .../library, the import is a same-dataset
#     atomic rename and qbittorrent removes the staging copy (Mullvad has no
#     port forwarding → leecher-only → nothing to seed/preserve).
#   - NAS (/mnt/nas/media/library): final library, read by Jellyfin and
#     written by Sonarr/Radarr at import time. Lives on draupnir's tank/media,
#     mounted over NFSv4 (draupnir exports it — hosts/draupnir/services/nfs.nix).
#   - NAS (/mnt/nas/essentials): curated keep-forever films on draupnir's
#     tank/essentials (snapshotted). Jellyfin adds it as a second Movies folder;
#     a keeper is moved here out of .../library/movies by hand.
#
# A shared `media` group spans the *arrs, qbittorrent, and jellyfin so they
# can traverse each other's paths without one impersonating the other. Each
# service module adds its own user to this group.
{
  # The `media`-group dirs are setgid (2775): the shared-group design only works
  # for *writes* if new subdirectories inherit group `media` (setgid) and stay
  # group-writable (the 7 in the middle). Without this, a folder created by one
  # media-group member (e.g. the yt2jelly daemon, or sonarr/radarr, or a manual
  # `yt2jelly` CLI run as sanfe) lands under the *creator's primary group* with
  # no group-write, and the next member is locked out with "Permission denied".
  # Pair with `umask 002` in the writers (see music-dl.nix) so files land 0664.
  # The download/library dirs live on the NAS and are created (setgid, group
  # media) by draupnir's nfs.nix, so asgard only anchors the automount parent.
  systemd.tmpfiles.rules = [
    # Parent for the NFS automounts below (/mnt/nas/{media,essentials}).
    # systemd creates the automount targets themselves; this just anchors /mnt/nas.
    "d /mnt/nas 0755 root root -"
  ];

  # gid pinned to 1500 — the cross-host contract with draupnir's export.
  # NFSv4 (sec=sys) maps permissions numerically, so this group's gid must be
  # identical on both boxes or Jellyfin/the arrs lose access to library files.
  #
  # GOTCHA (existing hosts): NixOS will NOT renumber an *existing* group's gid —
  # update-users-groups.pl warns and skips it to avoid orphaning files. This line
  # is correct for a from-scratch build, but asgard's `media` was already gid 990
  # (auto-assigned pre-NAS), so the 990→1500 move was a one-time manual step:
  #   sudo groupmod -g 1500 media
  #   sudo find /srv/media -gid 990 -exec chgrp media {} +   # fix orphaned files
  #   sudo systemctl restart sonarr radarr qbittorrent jellyfin
  # After that the running gid matches this declaration, so it's stable.
  users.groups.media.gid = 1500;

  # ── NAS mounts (draupnir tank over NFSv4) ────────────────────────────────
  # Automount: the units come up lazily on first access and don't block boot if
  # draupnir is briefly unreachable (soft,_netdev). tank/media = arr library;
  # tank/essentials = the curated keep set. draupnir's export ACL restricts both
  # to this host (192.168.1.54).
  fileSystems."/mnt/nas/media" = {
    device = "192.168.1.56:/tank/media";
    fsType = "nfs";
    options = ["x-systemd.automount" "noauto" "_netdev" "soft" "timeo=30" "nfsvers=4.2"];
  };
  fileSystems."/mnt/nas/essentials" = {
    device = "192.168.1.56:/tank/essentials";
    fsType = "nfs";
    options = ["x-systemd.automount" "noauto" "_netdev" "soft" "timeo=30" "nfsvers=4.2"];
  };
}
