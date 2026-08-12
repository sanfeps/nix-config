{
  config,
  lib,
  pkgs,
  ...
}:
# Yamtrack — self-hosted tracker for films, books, TV, games. Replaces nothing;
# it is the "what have I watched / read, and what did I rate it" log.
#
# Why here and not on draupnir (which runs Jellyfin): the Jellyfin link is a
# *webhook push* (Jellyfin POSTs play events to Yamtrack), so the two don't need
# to be co-located, and asgard already has the Podman backend, the shared
# Postgres, and the instance-wide dump timer. draupnir is the 8 GiB box with an
# Immich-ML OOM history — no reason to put a Django app there.
#
# The data that matters (the list + ratings) is backed up by ./appdata-backup.nix,
# not by this file.
let
  port = 8000;
  redisPort = 6380; # 6379 is Ghostfolio's own server
  domain = "yamtrack.lan.valgrindr.net";
in {
  sops.secrets."yamtrack/secret-key".mode = "0400";
  sops.secrets."yamtrack/db-password".mode = "0400";

  # Container reads runtime secrets from this env file. Everything non-secret
  # is a plain `environment` entry in the module.
  sops.templates."yamtrack.env" = {
    content = ''
      SECRET=${config.sops.placeholder."yamtrack/secret-key"}
      DB_PASSWORD=${config.sops.placeholder."yamtrack/db-password"}
    '';
    mode = "0400";
  };

  # Sync the Postgres role password to whatever sops currently holds. Idempotent.
  sops.templates."yamtrack-pgpass.sql" = {
    content = ''
      ALTER USER yamtrack WITH ENCRYPTED PASSWORD '${config.sops.placeholder."yamtrack/db-password"}';
    '';
    owner = "postgres";
    mode = "0400";
  };

  # Database on the SHARED instance (hosts/asgard/services/postgresql/). Own
  # database + own role, so Yamtrack cannot read the finance data and vice
  # versa — Postgres has no cross-database access without dblink/postgres_fdw.
  services.postgresql = {
    ensureDatabases = ["yamtrack"];
    ensureUsers = [
      {
        name = "yamtrack";
        ensureDBOwnership = true;
      }
    ];
    # ensureUsers creates the role passwordless; the oneshot below sets the
    # password right after Postgres starts so TCP+scram auth works.
    authentication = lib.mkAfter ''
      host yamtrack yamtrack 127.0.0.1/32 scram-sha-256
    '';
  };

  systemd.services.yamtrack-postgres-setup = {
    description = "Sync yamtrack Postgres role password from sops";
    # MUST be ordered after postgresql-SETUP, not just postgresql: nixpkgs runs
    # `ensureDatabases`/`ensureUsers` in a separate `postgresql-setup.service`,
    # so `After=postgresql.service` alone races it and the ALTER hits
    # `ERROR: role "yamtrack" does not exist` on a from-scratch deploy.
    after = ["postgresql-setup.service"];
    requires = ["postgresql-setup.service"];
    wantedBy = ["multi-user.target"];
    before = ["podman-yamtrack.service"];
    serviceConfig = {
      Type = "oneshot";
      User = "postgres";
      Group = "postgres";
      ExecStart = "${pkgs.postgresql_17}/bin/psql -v ON_ERROR_STOP=1 -f ${config.sops.templates."yamtrack-pgpass.sql".path}";
    };
  };

  # Dedicated Redis (Celery broker + metadata cache). Sharing Ghostfolio's is
  # supported upstream via REDIS_PREFIX, but a second server is one line and
  # keeps a stray FLUSHALL from taking out both apps.
  services.redis.servers.yamtrack = {
    enable = true;
    bind = "127.0.0.1";
    port = redisPort;
  };

  services.containers.yamtrack = {
    enable = true;
    inherit port;
    urls = "https://${domain}";
    redisUrl = "redis://127.0.0.1:${toString redisPort}";
    environmentFile = config.sops.templates."yamtrack.env".path;
  };

  services.caddy.virtualHosts.${domain}.extraConfig = ''
    reverse_proxy 127.0.0.1:${toString port}
  '';
}
