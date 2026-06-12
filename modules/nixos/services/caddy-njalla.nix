{
  config,
  pkgs,
  lib,
  ...
}:
with lib; let
  cfg = config.services.caddyNjalla;

  # caddy-dns/njalla has no tagged releases; pin to a commit via Go pseudo-version
  # (format: v0.0.0-YYYYMMDDHHMMSS-<short-sha>). Bump by replacing both fields.
  njallaPlugin = "github.com/caddy-dns/njalla@v0.0.0-20250823094507-f709141f1fe6";

  caddyWithNjalla = pkgs.caddy.withPlugins {
    plugins = [njallaPlugin];
    hash = "sha256-lus0hrUQhnmFeQXvJrYy9kcNkuI1cMmQ4xS7QscQ6tc=";
  };
in {
  options.services.caddyNjalla = {
    enable = mkEnableOption "Caddy bundled with the Njalla DNS-01 plugin for *.lan.valgrindr.net wildcard LE certs";
  };

  config = mkIf cfg.enable {
    # The Njalla token is shared infrastructure: every host that runs Caddy
    # with the wildcard cert needs it. Pin sopsFile to common so the secret
    # lives in one place regardless of which host enables this module.
    sops.secrets."njalla-api-token" = {
      sopsFile = ../../../hosts/common/secrets.yaml;
      mode = "0400";
    };

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
      globalConfig = ''
        acme_dns njalla {env.NJALLA_API_TOKEN}
      '';
    };

    networking.firewall.allowedTCPPorts = [80 443];

    environment.persistence."${config.hostSpec.persistFolder}".directories = [
      {
        directory = "/var/lib/caddy";
        user = "caddy";
        group = "caddy";
        mode = "0700";
      }
    ];
  };
}
