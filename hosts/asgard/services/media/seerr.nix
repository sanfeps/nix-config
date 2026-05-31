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
    openFirewall = false; # Pattern-B handles this.
    inherit port;
  };

  networking.firewall.extraCommands = ''
    iptables -I nixos-fw -p tcp --dport ${toString port} -s 192.168.1.55 -j nixos-fw-accept
  '';
}
