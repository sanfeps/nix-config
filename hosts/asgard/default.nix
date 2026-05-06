{
  inputs,
  lib,
  ...
}: {
  imports = [
    ./services

    #
    # ===== Hardware =====
    #
    ./hardware-configuration.nix

    #
    # ===== Disk Layout =====
    #
    inputs.disko.nixosModules.disko
    (import ../common/disks/btrfs-disk-uefi.nix {
      lib = lib;
      device = "/dev/sda";
    })

    #
    # ===== Required Config =====
    #
    ../common/core
    ../common/users/sanfe

    #
    # ===== Optional Config =====
    #
    ../optional/tailscale.nix
  ];

  # Jellyfin media server container
  #  services.containers.jellyfin = {
  #  enable = true;
  #  port = 8096;
  #  mediaPath = "/mnt/media";
  #  openFirewall = true;
  #  enableHardwareAcceleration = false;  # Server likely doesn't have /dev/dri
  #};

  networking = {
    hostName = "asgard";
    useDHCP = true;
  };

  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
    timeout = 3;
  };

  # Keep serial access for headless VM recovery in Proxmox.
  boot.kernelParams = ["console=ttyS0,115200" "console=tty1"];
  systemd.services."serial-getty@ttyS0".enable = true;
  boot.initrd.systemd.enable = true;

  system.stateVersion = "24.11";
}
