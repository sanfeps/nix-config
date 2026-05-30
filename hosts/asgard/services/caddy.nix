{...}: {
  # Asgard runs a Caddy instance solely to serve Firefly III. Firefly is a
  # PHP-FPM application served via a Unix socket; bifrost's Caddy cannot reach
  # the socket across hosts, so this one stays as an HTTP→FastCGI translator.
  # No TLS here: bifrost terminates TLS with the wildcard cert and proxies
  # HTTP to asgard:80 (firewall locks :80 to bifrost only — see below).
  #
  # Per-vhost config lives next to each service (see finances/firefly.nix);
  # this file only owns the daemon and its persistence.
  services.caddy.enable = true;

  # Port 80 is reachable only from bifrost (192.168.1.55). asgard still runs
  # the iptables backend, so add the source-filtered accept directly.
  networking.firewall.extraCommands = ''
    iptables -I nixos-fw -p tcp --dport 80 -s 192.168.1.55 -j nixos-fw-accept
  '';

  environment.persistence."/persist".directories = [
    {
      directory = "/var/lib/caddy";
      user = "caddy";
      group = "caddy";
      mode = "0700";
    }
  ];
}
