{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.services.containers.ghostfolio;
in {
  options.services.containers.ghostfolio = {
    enable = mkEnableOption "Ghostfolio investment portfolio tracker";

    image = mkOption {
      type = types.str;
      default = "docker.io/ghostfolio/ghostfolio:3.34.0@sha256:6e99d235d99dc01a205ad3cda46ab8b08fea6b732015b8c8906d5300017efa18";
      description = ''
        Container image to use for Ghostfolio.

        PINNED `version@digest` (see modules/nixos/CLAUDE.md). 3.34.0 is what
        asgard was already running when the pin was introduced 2026-08-12 — the
        pin was deliberately taken at the RUNNING version so it changed nothing
        on deploy. Note upstream was already at 3.49.0 by then: `:latest` never
        auto-upgraded, because the unit only pulls when the image is absent
        locally. Upgrading is now an explicit commit.
      '';
    };

    port = mkOption {
      type = types.port;
      default = 3333;
      description = "Port Ghostfolio listens on inside the host network namespace.";
    };

    host = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = ''
        Bind address for Ghostfolio's HTTP listener. Defaults to loopback so
        the service is only reachable through a local reverse proxy; set to
        0.0.0.0 when fronting the container from another host.
      '';
    };

    environmentFile = mkOption {
      type = types.path;
      description = ''
        Path to an env file containing the runtime secrets. Must define
        ACCESS_TOKEN_SALT, JWT_SECRET_KEY, and DATABASE_URL. Typically rendered
        by `sops.templates` so the secrets stay encrypted at rest.
      '';
    };

    redisHost = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Hostname Ghostfolio uses to reach Redis.";
    };

    redisPort = mkOption {
      type = types.port;
      default = 6379;
      description = "Port Ghostfolio uses to reach Redis.";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = config.virtualisation.oci-containers.backend == "podman";
        message = "Ghostfolio container requires the Podman backend. Import hosts/optional/podman.nix.";
      }
    ];

    virtualisation.oci-containers.containers.ghostfolio = {
      image = cfg.image;
      autoStart = true;

      environment = {
        NODE_ENV = "production";
        HOST = cfg.host;
        PORT = toString cfg.port;
        REDIS_HOST = cfg.redisHost;
        REDIS_PORT = toString cfg.redisPort;
      };

      environmentFiles = [cfg.environmentFile];

      extraOptions = [
        # Share the host's network namespace so Ghostfolio can reach
        # Postgres on 127.0.0.1 and Redis on the configured port without
        # extra bridges or DNS gymnastics.
        "--network=host"
      ];
    };
  };
}
