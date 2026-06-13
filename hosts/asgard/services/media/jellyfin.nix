{config, ...}:
# Jellyfin — playback server. Outside the VPN namespace (LAN-facing, no
# upside to confining playback to Mullvad and several downsides — DLNA,
# transcoding, client discovery all expect LAN visibility).
#
# Libraries: pointed at /mnt/nas/media/library via Jellyfin's web UI after
# first boot. Read-only access is what we want; the *arrs handle writes.
# Until the NAS lands, Jellyfin comes up empty — that's expected.
#
# Hardware acceleration: off. Asgard is a Proxmox VM with no /dev/dri
# exposed by default. Enabling later means passing through a GPU at the
# VM level + flipping `hardwareAcceleration.{enable,type,device}`.
#
# TLS: terminated by asgard's own Caddy (per-host-caddy Phase 4), which
# reverse-proxies https://jellyfin.lan.valgrindr.net → 127.0.0.1:8096. The
# WebUI binds 0.0.0.0 but no LAN firewall hole is opened, so on the LAN only
# loopback (Caddy) reaches it; plaintext never crosses the LAN.
#
# Tailnet guest access: :8096 IS opened on the tailscale0 interface only, so
# tailnet peers can reach Jellyfin directly over the WireGuard-encrypted link
# (http://asgard.ts.yggdrasil.lo:8096). WHICH peers is gated by the headscale
# ACL (group:guest → asgard:8096 in hosts/bifrost/services/headscale.nix), not
# by this firewall rule — the rule just lets tailnet traffic past the host
# firewall. No TLS here: the tailnet link is already encrypted.
{
  services.jellyfin = {
    enable = true;
    openFirewall = false; # local Caddy fronts it on loopback (LAN side).
    # dataDir, cacheDir, configDir all default under /var/lib/jellyfin —
    # see persistence below.
  };

  # Expose the WebUI on the tailnet interface only (not the LAN). Tailnet ACLs
  # decide who actually connects.
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [8096];

  # Read access to the future NAS-mounted library.
  users.users.jellyfin.extraGroups = ["media"];

  # Persist Jellyfin's data (library DB, user accounts, metadata, plugins,
  # config). Cache (/var/cache/jellyfin) stays ephemeral — it's transcoding
  # scratch and rebuilds cheaply.
  environment.persistence."${config.hostSpec.persistFolder}".directories = [
    {
      directory = "/var/lib/jellyfin";
      user = "jellyfin";
      group = "jellyfin";
      mode = "0700";
    }
  ];
}
