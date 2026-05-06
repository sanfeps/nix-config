{
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

    #
    # ===== Disk Layout =====
    #
    inputs.disko.nixosModules.disko
    (import ../common/disks/btrfs-luks-impermanence-disk.nix {
      lib = lib;
      config = config;
      device = "/dev/nvme0n1";
    })

    #
    # ===== Required Config =====
    #
    ../common/core
    ../common/core/workstation.nix
    ../common/users/sanfe

    #
    # ===== Optional Config =====
    #
    ../optional/greetd.nix
    ../optional/wireless.nix
    ../optional/tailscale.nix
    ../optional/podman.nix
  ];

  networking = {
    hostName = "raidho";
    useDHCP = true;
  };

  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
    timeout = 3;
  };

  boot.initrd.systemd.enable = true;

  programs.dconf.enable = true;

  security.pam.services.qs-lock = {};

  hardware.graphics.enable = true;

  system.stateVersion = "24.11";
}
