{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: {
  imports = [
    #
    # ===== Hardware =====
    #
    ./hardware-configuration.nix
    ./fan-control.nix

    #
    # ===== Disk Layout =====
    #
    # OS on the 128 GB NVMe (ex-UGOS disk; full-disk image backed up on midgard
    # before the wipe — see docs/draupnir-nas-implementation-plan.md).
    inputs.disko.nixosModules.disko
    (import ../common/disks/btrfs-disk-uefi.nix {
      lib = lib;
      device = "/dev/disk/by-id/nvme-YSO128GTLCW-E3C-2_511250514278001307";
    })
    # Data: raidz1 zpool "tank" across the 4 SATA bays.
    ./disko-data.nix

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

  networking = {
    hostName = "draupnir";
    # Required by ZFS (pool identity across reboots). Random, fixed forever;
    # changing it makes the pool look foreign to the OS.
    hostId = "fc571cf8";
    # Static-at-OS like asgard/bifrost (router still has no DHCP reservations).
    # .56 continues the asgard .54 / bifrost .55 sequence. enp1s0 is the
    # 2.5GbE port (MAC 6c:1f:f7:8e:2c:bc); name observed in the NixOS
    # installer on this hardware. The 10GbE port (enp4s0) is unused.
    useDHCP = false;
    interfaces.enp1s0.ipv4.addresses = [
      {
        address = "192.168.1.56";
        prefixLength = 24;
      }
    ];
    defaultGateway = "192.168.1.1";
    # AdGuard on bifrost first (resolves *.lan.valgrindr.net), Quad9 fallback.
    nameservers = [
      "192.168.1.55"
      "9.9.9.9"
    ];
  };

  #
  # ===== ZFS =====
  #
  # Keep the DEFAULT kernel on this host: ZFS lags bleeding-edge kernels
  # (no xanmod here). Pool layout lives in ./disko-data.nix.
  boot.supportedFilesystems = ["zfs"];
  boot.zfs.forceImportRoot = false;
  services.zfs.autoScrub = {
    enable = true;
    interval = "monthly";
    pools = ["tank"];
  };

  # ZED → ntfy push alerts (degraded pool, errors, scrub/resilver) via the
  # self-hosted ntfy on bifrost. VERBOSE makes scrub_finish notify too — the
  # monthly scrub push doubles as a heartbeat proving the pipeline works.
  #
  # The token must not land in the world-readable store, so the setting is a
  # command substitution: zed.rc values are rendered unescaped and *sourced* by
  # zedlets as root at event time, resolving $(cat …) against the sops-
  # materialized file at runtime.
  sops.secrets."zed-ntfy-token" = {};
  services.zfs.zed.settings = {
    ZED_NTFY_URL = "https://ntfy.lan.valgrindr.net";
    ZED_NTFY_TOPIC = "zfs-draupnir";
    ZED_NTFY_ACCESS_TOKEN = "$(cat ${config.sops.secrets."zed-ntfy-token".path})";
    ZED_NOTIFY_INTERVAL_SECS = 3600;
    ZED_NOTIFY_VERBOSE = true;
  };
  # The ntfy zedlet shells out to curl; make sure it's on the unit's PATH.
  systemd.services.zfs-zed.path = [pkgs.curl];

  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
    timeout = 3;
  };
  boot.initrd.systemd.enable = true;

  system.stateVersion = "26.05";
}
