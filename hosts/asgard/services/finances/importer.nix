{config, ...}: let
  virtualHost = "importer.asgard";
  fireflyHost = "firefly.asgard";
in {
  sops.secrets."finances/firefly-importer-app-key" = {
    owner = "firefly-iii-data-importer";
    mode = "0400";
  };
  sops.secrets."finances/firefly-access-token" = {
    owner = "firefly-iii-data-importer";
    mode = "0400";
  };

  services.firefly-iii-data-importer = {
    enable = true;
    enableNginx = false;
    group = "caddy";
    inherit virtualHost;
    settings = {
      APP_ENV = "production";
      APP_URL = "http://${virtualHost}";
      APP_KEY_FILE = config.sops.secrets."finances/firefly-importer-app-key".path;
      FIREFLY_III_URL = "http://${fireflyHost}";
      FIREFLY_III_ACCESS_TOKEN_FILE = config.sops.secrets."finances/firefly-access-token".path;
    };
  };

  # Upstream setup unit assumes its tmpfiles already exist, but doesn't
  # depend on systemd-tmpfiles-setup; without this the first boot races and
  # the maintenance script fails to find storage/logs.
  systemd.services.firefly-iii-data-importer-setup.after = ["systemd-tmpfiles-setup.service"];

  services.caddy.virtualHosts."http://${virtualHost}".extraConfig = ''
    root * ${config.services.firefly-iii-data-importer.package}/public
    php_fastcgi unix/${config.services.phpfpm.pools.firefly-iii-data-importer.socket}
    file_server
  '';

  # The importer talks to Firefly via its canonical hostname; resolve it
  # locally so APP_URL stays the same as the browser sees.
  networking.hosts."127.0.0.1" = [fireflyHost virtualHost];

  environment.persistence."${config.hostSpec.persistFolder}".directories = [
    {
      directory = "/var/lib/firefly-iii-data-importer";
      user = "firefly-iii-data-importer";
      group = "caddy";
      mode = "0710";
    }
  ];
}
