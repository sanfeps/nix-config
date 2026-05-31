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
# TLS: terminated on bifrost. Listening on 8096 plain HTTP is fine — the
# Pattern-B firewall locks the port to 192.168.1.55, so no plaintext
# traffic ever crosses the LAN unaddressed.
let
  port = 8096;
in {
  services.jellyfin = {
    enable = true;
    openFirewall = false; # Pattern-B handles this.
    # dataDir, cacheDir, configDir all default under /var/lib/jellyfin —
    # see persistence below.
  };

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

  # Pattern-B firewall: only bifrost reaches asgard:8096.
  networking.firewall.extraCommands = ''
    iptables -I nixos-fw -p tcp --dport ${toString port} -s 192.168.1.55 -j nixos-fw-accept
  '';
}
