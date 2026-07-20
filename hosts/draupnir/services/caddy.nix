{...}: {
  # Draupnir runs its own Caddy with a wildcard LE cert for *.lan.valgrindr.net
  # via Njalla DNS-01 — same per-host-ingress pattern as asgard/bifrost. Daemon
  # + plugin + sops env file + 80/443 + persistence are owned by the shared
  # services.caddyNjalla module (modules/nixos/services/caddy-njalla.nix).
  # Vhosts live inline next to each service (e.g. immich.nix).
  services.caddyNjalla.enable = true;

  # Bind every vhost to the LAN IP only by default (same pattern as asgard):
  # apps stay reachable on-LAN, and off-LAN to admins via bifrost's
  # 192.168.1.0/24 subnet route. Nothing listens on the tailnet IP unless a
  # vhost opts in explicitly. Merges with the module's `acme_dns njalla` line
  # (types.lines).
  services.caddy.globalConfig = "default_bind 192.168.1.56";
}
