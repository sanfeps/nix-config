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
    ../optional/greetd.nix
    ../optional/wireless.nix
  ];

  environment.systemPackages = with pkgs; [
    vulkan-tools
    mesa
    (mesa.drivers or mesa)
    nodejs
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
    adb.enable = true;
    dconf.enable = true;
  };
  
  programs.steam.enable = true;

  hardware.graphics.enable = true;

  #services.xserver = {
   # enable = true;
   # videoDrivers = [ "nvidia" ];
  #};
# hardware.nvidia.open = true;
# hardware = {
 # nvidia = {
  #    modesetting.enable = true;
   #   powerManagement.enable = true;

    #  prime = {

#	offload.enable = true;
#        intelBusId = "PCI:0:2:0";
#        nvidiaBusId = "PCI:2:0:0";
#      };
      # Usa el driver estable (puedes cambiarlo a legacy_390 si es necesario)
 #     package = config.boot.kernelPackages.nvidiaPackages.stable;
  #  };
#};
  system.stateVersion = "24.11";
}
