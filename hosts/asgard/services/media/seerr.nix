{...}:
# Seerr (formerly Jellyseerr) — request manager. Browses Jellyfin's library,
# accepts request submissions from users, forwards them to Sonarr/Radarr.
# Outside the VPN namespace (its outbound is TMDb metadata + the *arrs'
# loopback APIs — no torrent traffic).
#
# DynamicUser persistence trap: this module uses `DynamicUser = true` with
# `StateDirectory = "jellyseerr"` (because asgard.stateVersion = "24.11" <
# 26.05, so the old path is in play). Same shape as AdGuard's situation
# documented in the root CLAUDE.md — naïvely persisting /var/lib/jellyseerr
# collides with systemd's first-boot migration. Unlike Prowlarr, the seerr
# module has no `dataDir`-override escape hatch (overriding `configDir`
# breaks startup — nixpkgs issue #457739).
#
# Decision: leave Seerr's state ephemeral for now. The reconciler in
# Phase 6 declaratively reconfigures the Jellyfin/Sonarr/Radarr connections
# on every boot, so the "config" side of state is regenerated. User request
# history (a SQLite DB inside the state dir) IS lost on reboot — accept
# this as a known limitation until the /var/lib/private persistence
# recipe lands across the repo (AdGuard, Prowlarr Phase 3 already use
# their own workarounds; Seerr is the one that's stuck).
let
  port = 5055;
in {
  services.seerr = {
    enable = true;
    openFirewall = false; # Pattern-B handles this.
    inherit port;
    # configDir untouched — see header.
  };

  networking.firewall.extraCommands = ''
    iptables -I nixos-fw -p tcp --dport ${toString port} -s 192.168.1.55 -j nixos-fw-accept
  '';

  # TODO(seerr-persist): once a /var/lib/private impermanence recipe is
  # nailed down (AdGuard or a future migration), persist
  # /var/lib/private/jellyseerr so the request DB survives reboots.
}
