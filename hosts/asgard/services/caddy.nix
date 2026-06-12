{...}: {
  # Asgard runs its own Caddy with a wildcard LE cert for *.lan.valgrindr.net
  # via Njalla DNS-01. Daemon + plugin + sops env file + 80/443 + persistence
  # are owned by the shared services.caddyNjalla module
  # (modules/nixos/services/caddy-njalla.nix). Vhosts live inline next to each
  # service (e.g. immich.nix, finances/firefly.nix).
  #
  # Firefly's vhost still listens on plain :80 because TLS is currently
  # terminated on bifrost and the PHP-FPM socket bridge predates this
  # migration. Per-host-caddy Phase 3 folds Firefly into per-host TLS too —
  # at that point this file goes away entirely.
  services.caddyNjalla.enable = true;
}
