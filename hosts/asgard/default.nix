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
    ../optional/podman.nix
  ];

  networking = {
    hostName = "asgard";
    # Static-at-OS until the router supports DHCP reservations (mirrors bifrost).
    # The address matches asgard's prior DHCP lease, so AdGuard rewrites that
    # point *.lan.valgrindr.net at 192.168.1.54 keep working unchanged.
    useDHCP = false;
    interfaces.ens18.ipv4.addresses = [
      {
        address = "192.168.1.54";
        prefixLength = 24;
      }
    ];
    defaultGateway = "192.168.1.1";
    # Static means no DHCP-provided resolver: point at AdGuard on bifrost (so
    # *.lan names + the media reconciler's edge URLs resolve) with a Quad9
    # fallback for when AdGuard is down mid-rebuild.
    nameservers = [
      "192.168.1.55"
      "9.9.9.9"
    ];
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
