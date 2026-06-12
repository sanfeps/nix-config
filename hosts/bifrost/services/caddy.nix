{...}: {
  # Caddy daemon, Njalla DNS-01 plugin, sops env file, ACME global config,
  # firewall ports, and /var/lib/caddy persistence are owned by the shared
  # services.caddyNjalla module (modules/nixos/services/caddy-njalla.nix).
  # This file declares only vhosts.
  services.caddyNjalla.enable = true;

  services.caddy = {
    # Headscale lives on a PUBLIC domain (own cert via Njalla DNS-01 too) so
    # the world can reach the tailnet control plane. Router port-forwards
    # 80/443 to bifrost; the wildcard cert below covers only *.lan.valgrindr.net.
    virtualHosts."headscale.valgrindr.net".extraConfig = ''
      reverse_proxy 127.0.0.1:8080
    '';

    # Single wildcard vhost: one LE cert covers every *.lan.valgrindr.net
    # subdomain. Per-service routing happens via @host matchers + handle blocks.
    # adguard is local; home talks straight to its listener on asgard; firefly
    # bounces off asgard's tiny Caddy because PHP-FPM speaks FastCGI over a
    # Unix socket (HTTP can't cross hosts to that socket).
    virtualHosts."*.lan.valgrindr.net".extraConfig = ''
      @adguard host adguard.lan.valgrindr.net
      handle @adguard {
        reverse_proxy 127.0.0.1:3000
      }

      @firefly host firefly.lan.valgrindr.net
      handle @firefly {
        reverse_proxy 192.168.1.54:80
      }

      handle {
        respond "bifrost edge - unknown subdomain" 404
      }
    '';
  };
}
