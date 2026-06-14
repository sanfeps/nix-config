{...}:
# Filesystem layout for the media stack.
#
# Two tiers:
#
#   - Local on asgard (/srv/media/downloads): in-progress torrent data,
#     ephemeral. /srv already persists via hosts/common/core/optin-persistence,
#     so we only need the directories. Once an *arr imports a release to the
#     NAS library, qbittorrent removes the local source (Mullvad has no
#     port forwarding → leecher-only → no seeding ratio to preserve, so
#     "Remove from client when imported" is the natural flow).
#
#   - NAS (/mnt/nas/media/library): final library, read by Jellyfin and
#     written by Sonarr/Radarr at import time. Mount stays commented until
#     the NAS lands — same staging pattern as hosts/asgard/services/immich.nix.
#
# A shared `media` group spans the *arrs, qbittorrent, and jellyfin so they
# can traverse each other's paths without one impersonating the other. Each
# service module adds its own user to this group.
{
  systemd.tmpfiles.rules = [
    "d /srv/media           0755 root root  -"
    "d /srv/media/downloads 0775 root media -"

    # TEMP(no-nas): back /mnt/nas/media/library with local dirs so the whole
    # stack can be validated end-to-end before the NAS lands. When the
    # fileSystems block below is uncommented, the NFS automount overlays
    # /mnt/nas/media and these underlying dirs become invisible (harmless).
    # Remove these six lines at the same time the mount is wired in.
    "d /mnt/nas                    0755 root root  -"
    "d /mnt/nas/media              0755 root root  -"
    "d /mnt/nas/media/library      0775 root media -"
    "d /mnt/nas/media/library/tv     0775 root media -"
    "d /mnt/nas/media/library/movies 0775 root media -"
    "d /mnt/nas/media/library/music  0775 root media -"
  ];

  users.groups.media = {};

  # ──────────────────────────────────────────────────────────────────────────
  # NAS activation checklist (when the NAS lands):
  #
  #   1. Provision the NAS, expose `/media/library` (or chosen path) over
  #      NFS or CIFS. Decide on a stable gid for the `media` group and pin
  #      it here (`users.groups.media.gid = <n>;`) so the NAS-side
  #      anonuid/anongid + ACLs line up.
  #   2. Fill in the fileSystems block below with the real device + options,
  #      uncomment, remove this checklist.
  #   3. Verify Sonarr/Radarr (Phase 3) can write to /mnt/nas/media/library
  #      and Jellyfin (Phase 4) can read it.
  #
  # fileSystems."/mnt/nas/media" = {
  #   device = "TODO-nas.lan.valgrindr.net:/volume1/media";
  #   fsType = "nfs";
  #   options = [
  #     "x-systemd.automount"
  #     "noauto"
  #     "_netdev"
  #     "soft"
  #     "timeo=30"
  #   ];
  # };
  # ──────────────────────────────────────────────────────────────────────────
}
