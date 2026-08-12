{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.services.containers.yamtrack;
in {
  options.services.containers.yamtrack = {
    enable = mkEnableOption "Yamtrack self-hosted media tracker (films, books, TV, games)";

    image = mkOption {
      type = types.str;
      default = "ghcr.io/fuzzygrim/yamtrack:latest";
      description = "Container image to use for Yamtrack.";
    };

    port = mkOption {
      type = types.port;
      default = 8000;
      description = ''
        Port Yamtrack's bundled nginx listens on. NOTE: the image hardcodes
        `listen 8000` in its nginx.conf and exposes no bind-address knob, so
        with `--network=host` it binds 0.0.0.0 — there is no way to make it
        loopback-only. Keep the port out of `networking.firewall.allowedTCPPorts`
        and let the local Caddy front it; the firewall is what makes it private
        (same arrangement as Jellyfin on draupnir).
      '';
    };

    urls = mkOption {
      type = types.str;
      example = "https://yamtrack.lan.valgrindr.net";
      description = ''
        Public origin. Sets Yamtrack's `URLS`, which is a shortcut for both
        `CSRF` (trusted origins for POSTs behind a reverse proxy) and
        `ALLOWED_HOSTS`. Getting this wrong surfaces as CSRF failures on login
        rather than as an obvious error.
      '';
    };

    registration = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Whether new users may self-register. Default false: this is a
        single-user tracker behind LAN-only ingress, and the signup form would
        otherwise stay open to anyone who reaches it.
      '';
    };

    timeZone = mkOption {
      type = types.str;
      default = config.time.timeZone;
      defaultText = literalExpression "config.time.timeZone";
      description = "Timezone for the container (drives watch/read dates).";
    };

    database = {
      host = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = "PostgreSQL host. Reachable on loopback thanks to `--network=host`.";
      };
      port = mkOption {
        type = types.port;
        default = 5432;
        description = "PostgreSQL port.";
      };
      name = mkOption {
        type = types.str;
        default = "yamtrack";
        description = "PostgreSQL database name.";
      };
      user = mkOption {
        type = types.str;
        default = "yamtrack";
        description = "PostgreSQL role. Its password comes from `environmentFile` as DB_PASSWORD.";
      };
    };

    redisUrl = mkOption {
      type = types.str;
      default = "redis://127.0.0.1:6379";
      description = ''
        Redis URL for the cache and the Celery broker. Yamtrack supports
        sharing an instance via REDIS_PREFIX, but a dedicated server is one
        line and keeps Celery's queue keys out of another app's keyspace —
        prefer pointing this at its own `services.redis.servers.*`.
      '';
    };

    environmentFile = mkOption {
      type = types.path;
      description = ''
        Path to an env file holding the runtime secrets. Must define `SECRET`
        (Django signing key) and `DB_PASSWORD`. Typically rendered by
        `sops.templates` so the secrets stay encrypted at rest.
      '';
    };

    exportDir = mkOption {
      type = types.path;
      default = "/var/lib/yamtrack/exports";
      description = ''
        Host directory bind-mounted at `/exports` inside the container. The CSV
        export job writes here; something else is expected to ship the contents
        somewhere durable. Kept separate from the container's own state so the
        backup path never depends on container internals.
      '';
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = config.virtualisation.oci-containers.backend == "podman";
        message = "Yamtrack container requires the Podman backend. Import hosts/optional/podman.nix.";
      }
    ];

    systemd.tmpfiles.rules = [
      "d ${cfg.exportDir} 0750 root root -"
    ];

    virtualisation.oci-containers.containers.yamtrack = {
      image = cfg.image;
      autoStart = true;

      environment = {
        TZ = cfg.timeZone;
        URLS = cfg.urls;
        REGISTRATION =
          if cfg.registration
          then "True"
          else "False";
        REDIS_URL = cfg.redisUrl;
        # Presence of DB_HOST is what switches Yamtrack off its default SQLite.
        DB_HOST = cfg.database.host;
        DB_PORT = toString cfg.database.port;
        DB_NAME = cfg.database.name;
        DB_USER = cfg.database.user;
      };

      environmentFiles = [cfg.environmentFile];

      volumes = ["${cfg.exportDir}:/exports"];

      extraOptions = [
        # Share the host's network namespace so Yamtrack reaches Postgres and
        # Redis on 127.0.0.1 without a bridge or DNS gymnastics — same reasoning
        # as the Ghostfolio container.
        "--network=host"
      ];
    };
  };
}
