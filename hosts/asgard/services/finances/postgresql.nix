{
  config,
  pkgs,
  ...
}: {
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_17;
    enableTCPIP = false;
  };

  environment.persistence."${config.hostSpec.persistFolder}".directories = [
    {
      directory = "/var/lib/postgresql";
      user = "postgres";
      group = "postgres";
      mode = "0700";
    }
  ];
}
