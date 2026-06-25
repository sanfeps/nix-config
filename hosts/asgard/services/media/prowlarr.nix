{...}:
# Prowlarr — single source of truth for indexers. Confined to the Mullvad
# netns alongside qBittorrent and the *arrs.
#
# Persistence: the upstream module hardcodes `DynamicUser = true` +
# `StateDirectory = "prowlarr"`, so state lives at `/var/lib/private/prowlarr`
# (ExecStart always runs `-data=/var/lib/prowlarr`, a symlink into it). asgard's
# rootfs is NOT wiped on boot, so that path persists naturally — no
# `environment.persistence` entry needed (same call as seerr.nix). The
# DynamicUser `/var/lib/private` trap only bites on wipe-on-boot hosts
# (midgard); revisit there.
#
# We deliberately DO NOT set `dataDir`. A custom `dataDir` makes the module
# bind-mount it onto `/var/lib/private/prowlarr` AND drop a tmpfiles rule that
# re-asserts `root:root 0700` on the bind source on every tmpfiles run — which
# periodically strips the DynamicUser's own traverse permission and wedges the
# service with `SQLite error (14): EACCES` on its data dir (contents get left
# owned by the parked `nobody`/65534 uid; the web UI then 500s with a DryIoc
# `ArrayTypeMismatchException`). Letting systemd own the StateDirectory outright
# avoids that fight entirely.
let
  port = 9696;
in {
  services.prowlarr = {
    enable = true;
    openFirewall = false; # no LAN hole; local Caddy reaches it via the netns veth.
    # No dataDir override — see header comment. Data stays at the default
    # /var/lib/private/prowlarr; settings.server.port stays at the 9696 default.
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
