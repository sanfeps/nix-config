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

    #
    # ===== Services =====
    #
    ./services
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
    # AdGuard on bifrost ONLY — no public fallback, on purpose. systemd-
    # resolved treats listed servers as coequal (not ordered) and was observed
    # preferring 9.9.9.9, which NXDOMAINs every *.lan.valgrindr.net name
    # (silently breaking the ZED→ntfy pushes) and Njalla's NS domains
    # (breaking Caddy's DNS-01 propagation check — Quad9 blocklists them).
    # If bifrost is down, everything this host needs names for (ntfy, LE via
    # AdGuard's njalla routing) is down with it anyway.
    nameservers = ["192.168.1.55"];
  };

  #
  # ===== ZFS =====
  #
  # Keep the DEFAULT kernel on this host: ZFS lags bleeding-edge kernels
  # (no xanmod here). Pool layout lives in ./disko-data.nix.
  boot.supportedFilesystems = ["zfs"];
  boot.zfs.forceImportRoot = false;
  # Cap the ARC at 3 GiB: the box has 8 GiB total and now runs app services
  # too (Immich server + ML + Postgres + Redis). The ZFS default (50% of RAM)
  # plus those working sets leaves the kernel thrashing under ML jobs. ARC
  # gives memory back under pressure, but slowly — a hard cap is calmer.
  boot.kernelParams = ["zfs.zfs_arc_max=3221225472"];

  # Compressed RAM swap. The box has NO disk swap (btrfs rootfs — an NVMe
  # swapfile needs NOCOW/no-snapshot care), so a memory spike had nothing to
  # fall back on: on 2026-07-25 an Immich ML worker (.gunicorn) ballooned to
  # ~4.3 GiB and the OOM-killer took out the running photo-import CLI (and
  # ssh-agent, dbus). zram gives the kernel a cushion — cold anonymous pages
  # are zstd-compressed (~2-3x) instead of triggering a kill. It lives in RAM,
  # so it extends effective memory rather than adding real capacity; the real
  # long-term fix for Immich-with-ML on 8 GiB is more RAM. Keep ML stopped
  # during bulk imports regardless (systemctl stop immich-machine-learning).
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 100; # zram device up to ~RAM size; compressed, so cheap
  };
  # Nudge the kernel to actually use zram (compressed) before evicting caches.
  boot.kernel.sysctl."vm.swappiness" = 100;

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
