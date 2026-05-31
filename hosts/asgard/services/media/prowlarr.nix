{...}:
# Prowlarr — single source of truth for indexers. Confined to the Mullvad
# netns alongside qBittorrent and the *arrs.
#
# Persistence dance: the upstream module uses `DynamicUser = true` +
# `StateDirectory = "prowlarr"`, which normally drops state under
# `/var/lib/private/prowlarr` — a path that doesn't play nicely with
# `environment.persistence` (same trap as AdGuard, see root CLAUDE.md).
# Workaround: override `dataDir` to a custom path. When `dataDir !=
# /var/lib/prowlarr`, the module declares a `systemd.mounts` bind from
# `dataDir` → `/var/lib/private/prowlarr` plus a tmpfiles rule to create
# the source dir. We point it at `/srv/media/state/prowlarr` — `/srv` is
# already in the global persistence list, so the data survives reboots
# without an extra `environment.persistence.directories` entry.
let
  port = 9696;
in {
  services.prowlarr = {
    enable = true;
    openFirewall = false; # handled below per Pattern-B + VPN namespace.
    dataDir = "/srv/media/state/prowlarr";
    # settings.server.port stays at the 9696 default.
  };

  # Confine to the Mullvad netns. Prowlarr's outbound traffic (indexer
  # scrapes, captcha solves, etc.) goes through WireGuard.
  systemd.services.prowlarr.vpnConfinement = {
    enable = true;
    vpnNamespace = "mullvad";
  };

  vpnNamespaces.mullvad.portMappings = [
    {
      from = port;
      to = port;
      protocol = "tcp";
    }
  ];

  networking.firewall.extraCommands = ''
    iptables -I nixos-fw -p tcp --dport ${toString port} -s 192.168.1.55 -j nixos-fw-accept
  '';
}
