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
      withSwap = true;
      swapSize = "16";
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
    ../optional/tailscale.nix
    ../optional/podman.nix
    ../optional/gamemode.nix
    ../optional/zram.nix
    ../optional/sunshine.nix
    ../optional/xdg-portal.nix
  ];

  environment.systemPackages = with pkgs; [
    vulkan-tools
    mesa
    nodejs
    nvidia-vaapi-driver
  ];

  networking.hostName = "midgard";

  networking.firewall.allowedTCPPorts = [8080 8088];

  boot.loader = {
    systemd-boot.enable = true;
    systemd-boot.configurationLimit = 3;
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

  # udev rules for ST-Link / probe-rs (TFM firmware flashing).
  services.udev.packages = [pkgs.probe-rs-tools];

  hardware.nvidia = {
    modesetting.enable = true;
    open = true;
    nvidiaPersistenced = true;
    powerManagement.enable = true;
    package = config.boot.kernelPackages.nvidiaPackages.legacy_580;
  };
  system.stateVersion = "24.11";
}
