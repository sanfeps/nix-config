{...}: {
  # Asgard runs its own Caddy with a wildcard LE cert for *.lan.valgrindr.net
  # via Njalla DNS-01. Daemon + plugin + sops env file + 80/443 + persistence
  # are owned by the shared services.caddyNjalla module
  # (modules/nixos/services/caddy-njalla.nix). Vhosts live inline next to each
  # service (e.g. immich.nix, finances/firefly.nix, finances/ghostfolio.nix,
  # home-automation/*). Every asgard app now terminates TLS here — bifrost is
  # no longer in the request path for any of them.
  services.caddyNjalla.enable = true;
}
