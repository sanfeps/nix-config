{
  config,
  pkgs,
  ...
}: let
  virtualHost = "firefly.asgard";
in {
  sops.secrets."finances/firefly-app-key" = {
    owner = "firefly-iii";
    mode = "0400";
  };

  services.postgresql = {
    ensureDatabases = ["firefly-iii"];
    ensureUsers = [
      {
        name = "firefly-iii";
        ensureDBOwnership = true;
      }
    ];
  };

  services.firefly-iii = {
    enable = true;
    enableNginx = false;
    # Run firefly-iii under the caddy group so the PHP-FPM socket
    # is reachable by the Caddy reverse proxy.
    group = "caddy";
    inherit virtualHost;
    # Upstream pins nodejs-slim (no npm) in nativeBuildInputs while using
    # npmConfigHook, which fails with "npm: command not found".
    package = pkgs.firefly-iii.overrideAttrs (old: {
      nativeBuildInputs = (old.nativeBuildInputs or []) ++ [pkgs.nodejs];
    });
    settings = {
      APP_ENV = "production";
      APP_URL = "http://${virtualHost}";
      SITE_OWNER = "sanfelixguajardo@gmail.com";
      DB_CONNECTION = "pgsql";
      DB_DATABASE = "firefly-iii";
      DB_USERNAME = "firefly-iii";
      APP_KEY_FILE = config.sops.secrets."finances/firefly-app-key".path;
    };
  };

  services.caddy.virtualHosts."http://${virtualHost}".extraConfig = ''
    root * ${config.services.firefly-iii.package}/public
    php_fastcgi unix/${config.services.phpfpm.pools.firefly-iii.socket}
    file_server
  '';

  environment.persistence."${config.hostSpec.persistFolder}".directories = [
    {
      directory = "/var/lib/firefly-iii";
      user = "firefly-iii";
      group = "caddy";
      mode = "0710";
    }
  ];
}
