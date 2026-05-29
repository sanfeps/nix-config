{
  inputs,
  lib,
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

    #
    # ===== Services =====
    #
    ./services
  ];

  networking = {
    hostName = "bifrost";
    # Static-at-OS until the router supports DHCP reservations.
    useDHCP = false;
    interfaces.ens18.ipv4.addresses = [
      {
        address = "192.168.1.55";
        prefixLength = 24;
      }
    ];
    defaultGateway = "192.168.1.1";
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
