{...}: {
  # Asgard runs its own Caddy with a wildcard LE cert for *.lan.valgrindr.net
  # via Njalla DNS-01. Daemon + plugin + sops env file + 80/443 + persistence
  # are owned by the shared services.caddyNjalla module
  # (modules/nixos/services/caddy-njalla.nix). Vhosts live inline next to each
  # service (e.g. finances/firefly.nix, finances/ghostfolio.nix,
  # home-automation/*). Every asgard app now terminates TLS here — bifrost is
  # no longer in the request path for any of them.
  services.caddyNjalla.enable = true;

  # Bind every vhost to the LAN IP only by default. This carves out asgard's
  # tailnet IP (100.64.0.15) as a separate :443 listener that ONLY the Fluxer vhost
  # opts into (`bind` in services/fluxer/default.nix) — so guest tailnet users
  # granted `asgard:443` reach Fluxer and nothing else, while every other app
  # stays on the LAN IP (reachable on-LAN, and off-LAN to admins via the bifrost
  # subnet route). merges with the module's `acme_dns njalla` line (types.lines).
  services.caddy.globalConfig = "default_bind 192.168.1.54";

  # Let Caddy bind 100.64.0.15 even if tailscaled hasn't assigned it yet, so a
  # Caddy (re)start never blocks on tailscale being up. The other listeners on
  # the real LAN IP are unaffected; only the Fluxer-over-tailnet path waits for
  # the interface. Single-tenant VM, so non-local bind is not a concern here.
  boot.kernel.sysctl."net.ipv4.ip_nonlocal_bind" = 1;
}
