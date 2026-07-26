{
  config,
  pkgs,
  ...
}:
# Jellyfin on draupnir — playback server with Intel Quick Sync HW transcode.
#
# Moved here from asgard 2026-07-26. asgard is a QEMU VM whose only GPU is a
# virtual `card0` with no render node, so any file a client can't direct-play
# (HEVC video, E-AC-3/DDP audio — e.g. the x265 BluRay rips) forced a CPU
# transcode on a feature-masked virtual CPU and playback stuttered/froze. The
# NFS hop was NOT the bottleneck (measured ~116 MB/s, an order of magnitude
# over any single stream) — the fix is hardware transcoding, which asgard
# can't do without Proxmox GPU passthrough.
#
# draupnir is bare-metal Alder Lake (Pentium Gold 8505, Gen12 Quick Sync) with
# a real /dev/dri/renderD128, AND it owns the library locally on tank/media +
# tank/essentials — so this both fixes transcode and drops the NFS round-trip.
#
# Libraries (set ONCE in the Jellyfin UI — see draupnir CLAUDE.md):
#   Movies → /tank/media/library/movies  AND  /tank/essentials (snapshotted keep-set)
#   Shows  → /tank/media/library/series
#   Music  → /tank/media/library/music
# tank/essentials is added as a SECOND Movies folder so the curated keepers
# show alongside the churny arr-managed movies.
#
# HW transcode: the graphics stack + device-group access are wired in Nix
# below, but the acceleration itself is ACTIVATED in Dashboard → Playback
# (pick VAAPI or Intel QuickSync, device /dev/dri/renderD128). services.jellyfin
# exposes no Nix knob for the encoder settings, so that stays a one-time UI step.
#
# TLS: draupnir's own Caddy (services.caddyNjalla, already up for Immich)
# reverse-proxies https://jellyfin.lan.valgrindr.net → 127.0.0.1:8096. AdGuard
# on bifrost answers 192.168.1.56 for that name. WebUI binds 0.0.0.0 but no LAN
# firewall hole is opened, so on the LAN only loopback (Caddy) reaches it.
#
# Tailnet guest access: :8096 IS opened on tailscale0 only, so tailnet peers
# reach Jellyfin directly over the WireGuard link (http://draupnir.ts.yggdrasil.lo:8096).
# WHICH peers is gated by the headscale ACL (group:guest → draupnir:8096 in
# hosts/bifrost/services/headscale.nix), not this rule.
{
  services.jellyfin = {
    enable = true;
    openFirewall = false; # local Caddy fronts it on loopback (LAN side).
  };

  # Intel Quick Sync / VAAPI stack for HW decode+encode on the Alder Lake iGPU.
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver # iHD VAAPI driver (Gen9+)
      vpl-gpu-rt # oneVPL runtime — the QSV path on 11th-gen+ Intel
      intel-compute-runtime # OpenCL — HDR tone-mapping
    ];
  };

  # jellyfin needs: render (renderD128) + video (card0) for HW transcode;
  # media (gid 1500, the cross-host NFS contract, owned by nfs.nix) for read
  # access to the library datasets.
  users.users.jellyfin.extraGroups = ["media" "render" "video"];

  # Expose the WebUI on the tailnet interface only (not the LAN). Tailnet ACLs
  # decide who actually connects.
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [8096];

  # Local Caddy vhost (draupnir already enables services.caddyNjalla in caddy.nix).
  services.caddy.virtualHosts."jellyfin.lan.valgrindr.net".extraConfig = ''
    reverse_proxy 127.0.0.1:8096
  '';

  # Never scan an unmounted library: if the ZFS legacy mounts aren't up yet,
  # Jellyfin would index the empty mountpoint dirs on the NVMe rootfs and mark
  # the whole library missing.
  systemd.services.jellyfin.unitConfig.RequiresMountsFor = [
    "/tank/media"
    "/tank/essentials"
  ];

  # Persist Jellyfin's data (library DB, user accounts, metadata, plugins,
  # config). Cache (/var/cache/jellyfin) stays ephemeral — transcode scratch,
  # rebuilds cheaply.
  environment.persistence."${config.hostSpec.persistFolder}".directories = [
    {
      directory = "/var/lib/jellyfin";
      user = "jellyfin";
      group = "jellyfin";
      mode = "0700";
    }
  ];
}
