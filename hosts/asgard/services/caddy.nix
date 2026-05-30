{...}: {
  # Asgard runs a Caddy instance solely to serve Firefly III. Firefly is a
  # PHP-FPM application served via Unix socket; bifrost's Caddy cannot reach
  # the socket across hosts, so this one has to live here. AdGuard rewrites
  # firefly.lan.valgrindr.net directly to asgard (192.168.1.54), so LAN
  # clients hit this Caddy without going through bifrost.
  #
  # Per-vhost config lives next to each service (see finances/firefly.nix);
  # this file only owns the daemon and its persistence.
  services.caddy.enable = true;

  networking.firewall.allowedTCPPorts = [80];

  environment.persistence."/persist".directories = [
    {
      directory = "/var/lib/caddy";
      user = "caddy";
      group = "caddy";
      mode = "0700";
    }
  ];
}
