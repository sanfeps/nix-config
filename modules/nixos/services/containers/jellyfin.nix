# Jellyfin media server container module
# Provides a declarative way to run Jellyfin in a Podman container
#
# TODO: Migrate to quadlet-nix for proper rootless container support.
# Currently, containers run as systemd services under root, which is less secure.
# Quadlet-nix would allow running containers as user services via Home Manager.
# See: https://github.com/SEIAROTg/quadlet-nix
{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.services.containers.jellyfin;
in {
  options.services.containers.jellyfin = {
    enable = mkEnableOption "Jellyfin media server container";

    image = mkOption {
      type = types.str;
      default = "jellyfin/jellyfin:latest";
      description = "Container image to use for Jellyfin";
    };

    port = mkOption {
      type = types.port;
      default = 8096;
      description = "Port to expose Jellyfin web interface on";
    };

    mediaPath = mkOption {
      type = types.str;
      default = "/mnt/media";
      description = "Path to media files directory";
      example = "/mnt/external/media";
    };

    configPath = mkOption {
      type = types.str;
      default = "${config.hostSpec.persistFolder}/containers/jellyfin/config";
      description = "Path to Jellyfin configuration directory";
    };

    cachePath = mkOption {
      type = types.str;
      default = "${config.hostSpec.persistFolder}/containers/jellyfin/cache";
      description = "Path to Jellyfin cache directory";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to open the firewall port for Jellyfin";
    };

    enableHardwareAcceleration = mkOption {
      type = types.bool;
      default = true;
      description = "Enable hardware acceleration for video transcoding (requires /dev/dri)";
    };

    timezone = mkOption {
      type = types.str;
      default = config.time.timeZone or "UTC";
      description = "Timezone for the container";
    };

    extraVolumes = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Additional volume mounts for the container";
      example = [ "/mnt/music:/music:ro" "/mnt/photos:/photos:ro" ];
    };
  };

  config = mkIf cfg.enable {
    # Ensure Podman is enabled
    assertions = [
      {
        assertion = config.virtualisation.oci-containers.backend == "podman";
        message = "Jellyfin container requires Podman backend. Enable it with: virtualisation.oci-containers.backend = \"podman\"";
      }
    ];

    # Create required directories at boot using systemd-tmpfiles
    # These directories are created under /persist (via hostSpec.persistFolder),
    # so they automatically survive reboots with impermanence.
    # We use systemd.tmpfiles.rules instead of environment.persistence to avoid
    # circular dependency issues (trying to check if persistence exists while setting it).
    systemd.tmpfiles.rules = [
      "d ${cfg.configPath} 0755 root root -"
      "d ${cfg.cachePath} 0755 root root -"
      "d ${cfg.mediaPath} 0755 root root -"  # Create media directory as well
    ];

    # Define the Jellyfin container
    virtualisation.oci-containers.containers.jellyfin = {
      image = cfg.image;
      autoStart = true;

      ports = [
        "${toString cfg.port}:8096"
      ];

      volumes = [
        "${cfg.configPath}:/config"
        "${cfg.cachePath}:/cache"
        "${cfg.mediaPath}:/media:ro"  # Read-only media access for safety
      ] ++ cfg.extraVolumes;

      environment = {
        TZ = cfg.timezone;
        JELLYFIN_PublishedServerUrl = "http://localhost:${toString cfg.port}";
      };

      extraOptions =
        optionals cfg.enableHardwareAcceleration [
          "--device=/dev/dri:/dev/dri"  # For hardware video transcoding
        ] ++ [
          "--network=host"  # Use host networking for better performance
        ];
    };

    # Open firewall port if requested
    networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [ cfg.port ];
  };
}
