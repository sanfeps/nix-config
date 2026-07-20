{config, ...}:
# Immich on draupnir. The service contract (the upstream module, the
# local-Caddy vhost, /var/lib/immich persistence) lives in the reusable module
# `modules/homelab/services/immich` — this file only enables it and sets the
# draupnir-specific knobs.
#
# This is a FRESH install, not a data migration: the asgard instance was
# empty (pre-NAS scaffold, never loaded with photos), so it just gets
# decommissioned once this is validated — see
# docs/immich-draupnir-migration-runbook.md. The library lives directly on
# the raidz1 dataset at its canonical /tank/immich mountpoint; no asgard-era
# path compatibility to carry.
{
  homelab.services.immich = {
    enable = true;
    url = "immich.lan.valgrindr.net";
    # The tank/immich dataset (disko-data.nix). The upstream module's
    # tmpfiles rule chowns the mounted dir to immich:immich; Immich creates
    # its subtree (library/, upload/, thumbs/, …) from there.
    mediaLocation = "/tank/immich";
    # machineLearning stays on (default). 8 GiB is tight with ZFS ARC, so the
    # ARC is capped in ../default.nix; if memory pressure still shows up under
    # ML jobs, flipping this off is the next lever.
  };

  # Never let immich-server start against an unmounted library path — it
  # would write into the empty mountpoint dir on the NVMe rootfs.
  systemd.services.immich-server.unitConfig.RequiresMountsFor = [
    config.homelab.services.immich.mediaLocation
  ];
}
