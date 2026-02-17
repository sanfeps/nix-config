{
  pkgs,
  inputs,
  lib,
  config,
  ...
}: {
  imports = [
    #
    # ===== Hardware =====
    #
    ./hardware-configuration.nix
    inputs.hardware.nixosModules.common-cpu-amd
    inputs.hardware.nixosModules.common-pc-ssd

    #
    # ===== Disk Layout =====
    #
    inputs.disko.nixosModules.disko
    (import ../common/disks/btrfs-disk-bios.nix {
      lib = lib;
      config = config;
      device = "/dev/vda";
    })

    #
    # ===== Required Config =====
    #
    ../common/core
    ../common/users/sanfe

    #
    # ===== Optional Config =====
    #
    # ../optional/podman.nix
  ];

  # Jellyfin media server container
  #  services.containers.jellyfin = {
  #  enable = true;
  #  port = 8096;
  #  mediaPath = "/mnt/media";
  #  openFirewall = true;
  #  enableHardwareAcceleration = false;  # Server likely doesn't have /dev/dri
  #};

  environment.systemPackages = with pkgs; [
  ];

  networking = {
    hostName = "asgard";
    useDHCP = true;
  };

  # Disko handles GRUB installation automatically for BIOS boot
  boot.loader.timeout = 3;

  # Enable serial console for VPS console access
  boot.kernelParams = ["console=ttyS0,115200" "console=tty1"];
  systemd.services."serial-getty@ttyS0".enable = true;
  boot.initrd = {
    systemd.enable = true;
    # This mostly mirrors what is generated on qemu from nixos-generate-config in hardware-configuration.nix
    kernelModules = [
      "xhci_pci"
      "ohci_pci"
      "ehci_pci"
      "virtio_pci"
      "ahci"
      "usbhid"
      "sr_mod"
      "virtio_blk"
      #   "nvidia"
      #   "i915"
      #   "nvidia_modeset"
      #   "nvidia_drm"
    ];
  };

  boot = {
    kernelPackages = pkgs.linuxKernel.packages.linux_xanmod_latest;
    binfmt.emulatedSystems = [
      "aarch64-linux"
      "i686-linux"
    ];
  };

  programs = {
  };

  system.stateVersion = "24.11";
}
