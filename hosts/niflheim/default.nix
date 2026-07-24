# niflheim — offsite backup box. Intermittently connected (~monthly), pulls a
# raw ZFS replica of draupnir's irreplaceable datasets to a local single-disk
# pool `cold`, then powers itself off. Full design: hosts/niflheim/CLAUDE.md +
# docs/immich-offsite-backup-plan.md.
#
# SCAFFOLD: hardware-specific values are TODO(hw); the flake entry is commented
# out until the box exists (see flake.nix).
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

    #
    # ===== Disk Layout =====
    #
    # OS on the NVMe (plain BTRFS, no wipe, no LUKS — same as draupnir).
    inputs.disko.nixosModules.disko
    (import ../common/disks/btrfs-disk-uefi.nix {
      lib = lib;
      device = "/dev/disk/by-id/REPLACE-ME-os-nvme"; # TODO(hw)
    })
    # Data: single-disk zpool "cold" on the big HDD.
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
    hostName = "niflheim";
    # ZFS pool identity — random, fixed forever (changing it makes `cold` look
    # foreign). TODO(hw): generate on first install with
    #   head -c4 /dev/urandom | od -A none -t x4
    # and pin the value here.
    hostId = "beefcafe"; # TODO(hw): replace with a real random id

    # DHCP, NOT a static LAN IP: niflheim relocates offsite, so it can't own a
    # fixed 192.168.1.x like asgard/bifrost/draupnir. It addresses via tailscale
    # (100.64.0.x) everywhere — on the home LAN during the seed and at the
    # offsite site afterwards. DNS + LAN reachability (for ntfy) come over the
    # tailnet; see CLAUDE.md re: accept-routes offsite.
    useDHCP = true;
  };

  #
  # ===== ZFS =====
  #
  # Keep the DEFAULT kernel (ZFS lags bleeding-edge kernels; no xanmod), same
  # rationale as draupnir. Pool layout is in ./disko-data.nix.
  boot.supportedFilesystems = ["zfs"];
  boot.zfs.forceImportRoot = false;
  # NOTE: no scheduled autoScrub — a monthly timer barely fires on a box that's
  # powered off most of the month. Scrubbing is left best-effort/manual (or a
  # future addition to the on-connect workflow). See CLAUDE.md.

  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
    timeout = 3;
  };
  boot.initrd.systemd.enable = true;

  system.stateVersion = "26.05"; # TODO(hw): match the installer's channel
}
