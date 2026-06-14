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

  # Prefer IPv4 for outbound dual-stack connections. Tailscale assigns asgard an
  # IPv6 ULA (fd7a:…) on tailscale0, which makes glibc's AI_ADDRCONFIG advertise
  # IPv6 capability and return AAAA records first — but asgard has NO public IPv6
  # route, so any naive client that just connects to the first address (Python's
  # urllib and similar non-Happy-Eyeballs HTTP stacks) hits a dead IPv6 address
  # and hangs/fails, while curl/.NET fall back to v4. Bumping IPv4-mapped
  # addresses to the top of the precedence table makes getaddrinfo hand back IPv4
  # first. IPv6 stays enabled (tailscale keeps working); we just stop preferring
  # the unreachable path. Harmless on a v4-only LAN, and it heads off a whole
  # class of confusing "works in curl, fails in the app" bugs. (Default RFC-3484
  # table with ::ffff:0:0/96 raised 10→100; providing any precedence value
  # replaces the table, so the other rows are reproduced to keep IPv6 ordering.)
  networking.getaddrinfo.precedence = {
    "::1/128" = 50;
    "::/0" = 40;
    "2002::/16" = 30;
    "::/96" = 20;
    "::ffff:0:0/96" = 100;
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
