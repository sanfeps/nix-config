# Base Podman configuration for container services
# This provides the foundation for declarative container management
{ pkgs, ... }: {
  # Enable common container config files in /etc/containers
  virtualisation.containers.enable = true;

  virtualisation.podman = {
    enable = true;

    # Create a `docker` alias for podman (compatibility with docker-compose and other tools)
    dockerCompat = true;

    # Required for containers to communicate with each other via container names
    defaultNetwork.settings.dns_enabled = true;

    # Enable docker socket for compatibility
    # This allows both rootful (systemd services) and rootless (user) usage
    dockerSocket.enable = true;

    # Enable auto-pruning of unused images to save disk space
    autoPrune = {
      enable = true;
      dates = "weekly";
    };
  };

  # Set the backend for oci-containers to use Podman
  virtualisation.oci-containers.backend = "podman";

  # Useful tools for container management
  environment.systemPackages = with pkgs; [
    podman-compose  # Docker-compose compatibility
    podman-tui      # Terminal UI for managing containers
  ];
}
