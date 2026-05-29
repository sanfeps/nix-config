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
      default = "ghostfolio/ghostfolio:latest";
      description = "Container image to use for Ghostfolio.";
    };

    port = mkOption {
      type = types.port;
      default = 3333;
      description = "Port Ghostfolio listens on inside the host network namespace.";
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
        HOST = "0.0.0.0";
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
