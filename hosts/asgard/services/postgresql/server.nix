{
  config,
  lib,
  pkgs,
  ...
}: {
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_17;
    # TCP enabled on loopback only so containerized services (Ghostfolio, etc.)
    # can connect via 127.0.0.1 over `--network=host` without exposing Postgres
    # to the LAN.
    enableTCPIP = true;
    settings.listen_addresses = lib.mkForce "127.0.0.1";
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
