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
    (import ../common/disks/btrfs-luks-impermanence-disk.nix {
      lib = lib;
      config = config;
      device = "/dev/nvme0n1";
    })

    #
    # ===== Required Config =====
    #
    ../common/core
    ../common/users/sanfe

    #
    # ===== Optional Config =====
    #
    ../optional/greetd.nix
    ../optional/podman.nix
    ../optional/gamemode.nix
  ];

  environment.systemPackages = with pkgs; [
    vulkan-tools
    mesa
    (mesa.drivers or mesa)
    nodejs
    nvidia-vaapi-driver
  ];

  networking = {
    hostName = "midgard";
    useDHCP = true;
  };

  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
    timeout = 3;
  };
  boot.initrd = {
    systemd.enable = true;
    kernelModules = [
      "nvidia"
      "nvidia_modeset"
      "nvidia_uvm"
      "nvidia_drm"
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
    dconf.enable = true;
  };

  security.pam.services.qs-lock = {};

  programs.steam.enable = true;
  
  hardware.graphics.enable = true;

  services.xserver.videoDrivers = ["nvidia"];

  hardware.nvidia = {
    modesetting.enable = true;
    open = true;
    powerManagement.enable = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };
  system.stateVersion = "24.11";
}
