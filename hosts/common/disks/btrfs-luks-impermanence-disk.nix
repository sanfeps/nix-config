# NOTE: ... is needed because dikso passes diskoFile
{
  lib,
  config,
  device ? "/dev/vda",
  withSwap ? false,
  swapSize ? "2",
  ...
}: let
  luks_name = "${config.networking.hostName}-crypt";

  # Wipe @root subvolume
  wipeScript = ''
    BTRFS_DEV="/dev/mapper/${luks_name}"
    MOUNT_POINT="/btrfs_tmp"
    ROOT_SUBVOL="@root"

    mkdir -p "$MOUNT_POINT"
    mount "$BTRFS_DEV" "$MOUNT_POINT"

    echo "Cleaning root subvolume"
           btrfs subvolume list -o "$MOUNT_POINT/$ROOT_SUBVOL" | cut -f9 -d ' ' | sort |
           while read -r subvolume; do
             btrfs subvolume delete "$MOUNT_POINT/$subvolume"
           done && btrfs subvolume delete "$MOUNT_POINT/$ROOT_SUBVOL"

           echo "Restoring blank subvolume"
           btrfs subvolume create "$MOUNT_POINT/$ROOT_SUBVOL"

    umount "$MOUNT_POINT"
  '';
in {
  disko.devices = {
    disk = {
      disk0 = {
        type = "disk";
        device = device;
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              priority = 1;
              name = "ESP";
              start = "1M";
              end = "512M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = ["defaults"];
              };
            };
            luks = {
              size = "100%";
              content = {
                type = "luks";
                name = luks_name;
                passwordFile = "/tmp/disko-password";
                # Subvolumes must set a mountpoint in order to be mounted,
                # unless their parent is mounted
                content = {
                  type = "btrfs";
                  extraArgs = ["-f"]; # Force overwrite existing partition
                  subvolumes = {
                    "@root" = {
                      mountpoint = "/";
                      mountOptions = [
                        "compress=zstd"
                        "noatime"
                      ];
                    };
                    "@nix" = {
                      mountpoint = "/nix";
                      mountOptions = [
                        "compress=zstd"
                        "noatime"
                      ];
                    };
                    "@persist" = {
                      mountpoint = "${config.hostSpec.persistFolder}";
                      mountOptions = [
                        "compress=zstd"
                        "noatime"
                      ];
                    };
                    "@swap" = lib.mkIf withSwap {
                      mountpoint = "/.swapvol";
                      swap.swapfile.size = "${swapSize}G";
                    };
                  };
                };
              };
            };
          };
        };
      };
    };
  };

  fileSystems.${config.hostSpec.persistFolder}.neededForBoot = true;

  boot.initrd = {
    supportedFilesystems = ["btrfs"];
    systemd.services.restore-root = {
      description = "Rollback btrfs rootfs";
      wantedBy = ["initrd.target"];
      requires = ["dev-mapper-${config.networking.hostName}\\x2dcrypt.device"];
      after = [
        "dev-mapper-${config.networking.hostName}\\x2dcrypt.device"
      ];
      before = ["sysroot.mount"];
      unitConfig.DefaultDependencies = "no";
      serviceConfig.Type = "oneshot";
      script = wipeScript;
    };
  };
}
