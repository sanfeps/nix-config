{
  config,
  lib,
  pkgs,
  ...
}: let
  port = 3333;
in {
  sops.secrets."finances/ghostfolio-access-token-salt".mode = "0400";
  sops.secrets."finances/ghostfolio-jwt-secret".mode = "0400";
  sops.secrets."finances/ghostfolio-db-password".mode = "0400";

  # Container reads runtime secrets from this env file.
  sops.templates."ghostfolio.env" = {
    content = ''
      ACCESS_TOKEN_SALT=${config.sops.placeholder."finances/ghostfolio-access-token-salt"}
      JWT_SECRET_KEY=${config.sops.placeholder."finances/ghostfolio-jwt-secret"}
      DATABASE_URL=postgresql://ghostfolio:${config.sops.placeholder."finances/ghostfolio-db-password"}@127.0.0.1:5432/ghostfolio
    '';
    mode = "0400";
  };

  # Sync the Postgres role password to whatever sops currently holds. Idempotent.
  sops.templates."ghostfolio-pgpass.sql" = {
    content = ''
      ALTER USER ghostfolio WITH ENCRYPTED PASSWORD '${config.sops.placeholder."finances/ghostfolio-db-password"}';
    '';
    owner = "postgres";
    mode = "0400";
  };

  services.postgresql = {
    ensureDatabases = ["ghostfolio"];
    ensureUsers = [
      {
        name = "ghostfolio";
        ensureDBOwnership = true;
      }
    ];
    # The role is created passwordless by ensureUsers; the oneshot below sets
    # the password right after Postgres starts so TCP+scram auth works.
    authentication = lib.mkAfter ''
      host ghostfolio ghostfolio 127.0.0.1/32 scram-sha-256
    '';
  };

  systemd.services.ghostfolio-postgres-setup = {
    description = "Sync ghostfolio Postgres role password from sops";
    after = ["postgresql.service"];
    requires = ["postgresql.service"];
    wantedBy = ["multi-user.target"];
    before = ["podman-ghostfolio.service"];
    serviceConfig = {
      Type = "oneshot";
      User = "postgres";
      Group = "postgres";
      ExecStart = "${pkgs.postgresql_17}/bin/psql -v ON_ERROR_STOP=1 -f ${config.sops.templates."ghostfolio-pgpass.sql".path}";
    };
  };

  services.redis.servers.ghostfolio = {
    enable = true;
    bind = "127.0.0.1";
    port = 6379;
  };

  services.containers.ghostfolio = {
    enable = true;
    inherit port;
    environmentFile = config.sops.templates."ghostfolio.env".path;
  };

  # Container binds 0.0.0.0:3333 (its image hardcodes HOST=0.0.0.0). Caddy on
  # bifrost reverse-proxies the public name to this port; the rest of the LAN
  # must not see it. extraCommands (iptables) because asgard still runs the
  # iptables backend.
  networking.firewall.extraCommands = ''
    iptables -I nixos-fw -p tcp --dport ${toString port} -s 192.168.1.55 -j nixos-fw-accept
  '';
}
