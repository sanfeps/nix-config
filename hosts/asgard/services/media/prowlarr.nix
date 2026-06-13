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
    openFirewall = false; # no LAN hole; local Caddy reaches it via the netns veth.
    dataDir = "/srv/media/state/prowlarr";
    # settings.server.port stays at the 9696 default.
  };

  # Confine to the Mullvad netns. Prowlarr's outbound traffic (indexer
  # scrapes, captcha solves, etc.) goes through WireGuard.
  systemd.services.prowlarr.vpnConfinement = {
    enable = true;
    vpnNamespace = "mullvad";
  };

  # See sonarr.nix / media/caddy.nix: portMappings stays for the in-namespace
  # veth INPUT ACCEPT rule; local Caddy reaches Prowlarr at 192.168.15.1:${toString port}.
  vpnNamespaces.mullvad.portMappings = [
    {
      from = port;
      to = port;
      protocol = "tcp";
    }
  ];
}
