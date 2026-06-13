{
  config,
  lib,
  ...
}:
# Immich — self-hosted photo/video library, as a reusable homelab service.
#
# Thin wrapper (see docs/services-reusable-modules-plan.md): exposes the few
# knobs a host actually varies (url, mediaLocation, port, ML) and wires the
# rest — the upstream services.immich module, the local-Caddy vhost, and
# persistence — itself. Drop into services.immich.* directly for anything not
# surfaced here. Host-specific storage backing (e.g. the pre-NAS tmpfiles dir
# on asgard) stays in the host file; this module is fleet-generic.
with lib; let
  cfg = config.homelab.services.immich;
in {
  options.homelab.services.immich = {
    enable = mkEnableOption "Immich self-hosted photo/video library";

    url = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "immich.lan.valgrindr.net";
      description = ''
        FQDN to front Immich with on the host's local Caddy. When non-null a
        `services.caddy.virtualHosts.<url>` reverse-proxy to the Immich
        listener is declared — requires a Caddy on the same host (e.g.
        `services.caddyNjalla.enable`). Null = backend only, no vhost.
      '';
    };

    host = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Address Immich binds to. Loopback by default so only the local Caddy reaches it.";
    };

    port = mkOption {
      type = types.port;
      default = 2283;
      description = "Port Immich's server binds to.";
    };

    mediaLocation = mkOption {
      type = types.path;
      example = "/mnt/nas/immich";
      description = "Library root (originals, thumbnails, encoded video). The host is responsible for backing this path.";
    };

    machineLearning = mkOption {
      type = types.bool;
      default = true;
      description = "Enable face/object embedding (CPU-heavy). Disable on constrained hosts.";
    };
  };

  config = mkIf cfg.enable {
    services.immich = {
      enable = true;
      inherit (cfg) host port mediaLocation;
      machine-learning.enable = cfg.machineLearning;
      # Postgres (shared instance, peer auth via /run/postgresql) + a dedicated
      # Redis are auto-configured by the upstream module; defaults are right.
    };

    # Front Immich with the host's local Caddy when a url is given.
    services.caddy.virtualHosts = mkIf (cfg.url != null) {
      ${cfg.url}.extraConfig = ''
        reverse_proxy ${cfg.host}:${toString cfg.port}
      '';
    };

    # Service state (DB, thumbnails, encoded video, ML models). Photo originals
    # live under mediaLocation, so they are intentionally not persisted here.
    environment.persistence."${config.hostSpec.persistFolder}".directories = [
      {
        directory = "/var/lib/immich";
        user = config.services.immich.user;
        group = config.services.immich.group;
        mode = "0700";
      }
    ];
  };
}
