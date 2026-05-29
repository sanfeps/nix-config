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
    # Phase 2 validation vhost. Real reverse-proxies land in Phase 3.
    virtualHosts."test.lan.valgrindr.net".extraConfig = ''
      respond "bifrost edge - phase 2 ok"
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
