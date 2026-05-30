{
  config,
  pkgs,
  lib,
  ...
}: let
  # caddy-dns/njalla has no tagged releases; pin to a commit via Go pseudo-version
  # (format: v0.0.0-YYYYMMDDHHMMSS-<short-sha>). Bump by replacing both fields.
  njallaPlugin = "github.com/caddy-dns/njalla@v0.0.0-20250823094507-f709141f1fe6";

  caddyWithNjalla = pkgs.caddy.withPlugins {
    plugins = [njallaPlugin];
    hash = "sha256-lus0hrUQhnmFeQXvJrYy9kcNkuI1cMmQ4xS7QscQ6tc=";
  };
in {
  sops.secrets."njalla-api-token".mode = "0400";

  # Caddy reads NJALLA_API_TOKEN via environmentFile for the acme_dns directive.
  sops.templates."caddy-env" = {
    content = "NJALLA_API_TOKEN=${config.sops.placeholder."njalla-api-token"}\n";
    owner = "caddy";
    mode = "0400";
  };

  services.caddy = {
    enable = true;
    package = caddyWithNjalla;
    environmentFile = config.sops.templates."caddy-env".path;
    # Wildcard cert for *.lan.valgrindr.net via Njalla DNS-01.
    globalConfig = ''
      acme_dns njalla {env.NJALLA_API_TOKEN}
    '';
    # Headscale lives on a PUBLIC domain (own cert via Njalla DNS-01 too) so
    # the world can reach the tailnet control plane. Router port-forwards
    # 80/443 to bifrost; the wildcard cert below covers only *.lan.valgrindr.net.
    virtualHosts."headscale.valgrindr.net".extraConfig = ''
      reverse_proxy 127.0.0.1:8080
    '';

    # Single wildcard vhost: one LE cert covers every *.lan.valgrindr.net
    # subdomain. Per-service routing happens via @host matchers + handle blocks.
    # Phase 3a state: ghostfolio and home still live on asgard; bifrost just
    # proxies. adguard goes to the local AdGuard webUI on this host.
    virtualHosts."*.lan.valgrindr.net".extraConfig = ''
      @adguard host adguard.lan.valgrindr.net
      handle @adguard {
        reverse_proxy 127.0.0.1:3000
      }

      @ghostfolio host ghostfolio.lan.valgrindr.net
      handle @ghostfolio {
        reverse_proxy 192.168.1.54:3333
      }

      @home host home.lan.valgrindr.net
      handle @home {
        reverse_proxy 192.168.1.54:8123
      }

      handle {
        respond "bifrost edge - unknown subdomain" 404
      }
    '';
  };

  networking.firewall.allowedTCPPorts = [80 443];

  environment.persistence."/persist".directories = [
    {
      directory = "/var/lib/caddy";
      user = "caddy";
      group = "caddy";
      mode = "0700";
    }
  ];
}
