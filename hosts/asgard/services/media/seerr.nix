{...}:
# Seerr (formerly Jellyseerr) — request manager. Browses Jellyfin's library,
# accepts request submissions from users, forwards them to Sonarr/Radarr.
# Outside the VPN namespace (its outbound is TMDb metadata + the *arrs'
# loopback APIs — no torrent traffic).
#
# The nixpkgs module uses `DynamicUser = true` + `StateDirectory = "jellyseerr"`,
# which bind-mounts /var/lib/private/jellyseerr → /var/lib/jellyseerr. On
# asgard the rootfs is NOT wiped on boot (btrfs-disk-uefi.nix layout — no
# postDeviceCommands, no snapshot rollback), so the state survives reboots
# naturally without any `environment.persistence` declaration. The trap
# documented in media/CLAUDE.md only applies to hosts using the
# `btrfs-luks-impermanence-disk.nix` layout (currently only midgard).
let
  port = 5055;
in {
  services.seerr = {
    enable = true;
    openFirewall = false; # local Caddy fronts it on loopback.
    inherit port;
  };

  # Fronted by asgard's own Caddy (per-host-caddy Phase 4) at
  # https://seerr.lan.valgrindr.net → 127.0.0.1:${toString port}. Vhost lives in
  # media/caddy.nix; no firewall hole needed (loopback only).
}
