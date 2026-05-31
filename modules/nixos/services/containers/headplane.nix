{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.services.containers.headplane;
in {
  options.services.containers.headplane = {
    enable = mkEnableOption "Headplane, a web UI for Headscale";

    image = mkOption {
      type = types.str;
      default = "ghcr.io/tale/headplane:latest";
      description = "Container image to use for Headplane.";
    };

    port = mkOption {
      type = types.port;
      default = 3001;
      description = ''
        Port Headplane's web UI listens on (host network namespace, since the
        container uses `--network=host` so it can reach headscale on
        127.0.0.1). Must match the `server.port` set inside `configFile`.
      '';
    };

    configFile = mkOption {
      type = types.path;
      description = ''
        Path to Headplane's YAML config (mounted read-only at
        /etc/headplane/config.yaml inside the container). Headplane 0.6+ no
        longer reads server / headscale settings from env vars — the YAML is
        the only supported format. Typically rendered by `sops.templates` so
        the cookie secret stays encrypted at rest.
      '';
    };

    headscaleConfigPath = mkOption {
      type = types.path;
      default = "/etc/headscale/config.yaml";
      description = ''
        Host path of headscale's rendered config.yaml. Mounted read-only into
        the container so Headplane can surface ACLs, OIDC settings, etc.
      '';
    };

    stateDir = mkOption {
      type = types.path;
      default = "/var/lib/headplane";
      description = "Host directory for Headplane persistent state.";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = config.virtualisation.oci-containers.backend == "podman";
        message = "Headplane container requires the Podman backend. Import hosts/optional/podman.nix.";
      }
    ];

    systemd.tmpfiles.rules = [
      "d ${cfg.stateDir} 0700 root root -"
    ];

    virtualisation.oci-containers.containers.headplane = {
      image = cfg.image;
      autoStart = true;

      volumes = [
        "${cfg.configFile}:/etc/headplane/config.yaml:ro"
        "${cfg.headscaleConfigPath}:/etc/headscale/config.yaml:ro"
        "${cfg.stateDir}:/var/lib/headplane"
      ];

      extraOptions = [
        # Share the host network namespace so Headplane can reach headscale on
        # 127.0.0.1:8080 and bind its own port without bridge gymnastics.
        "--network=host"
      ];
    };
  };
}
