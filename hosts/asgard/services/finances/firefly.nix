{config, ...}: let
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
    enableNginx = true;
    inherit virtualHost;
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

  networking.firewall.allowedTCPPorts = [80];

  environment.persistence."${config.hostSpec.persistFolder}".directories = [
    {
      directory = "/var/lib/firefly-iii";
      user = "firefly-iii";
      group = "nginx";
      mode = "0710";
    }
  ];
}
