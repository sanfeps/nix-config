# BIOS/Legacy boot compatible disk layout for VPS
# NOTE: ... is needed because disko passes diskoFile
{
  lib,
  device ? "/dev/vda",
  withSwap ? false,
  swapSize ? "2",
  ...
}: {
  disko.devices = {
    disk = {
      disk0 = {
        type = "disk";
        device = device;
        content = {
          type = "gpt";
          partitions = {
            boot = {
              priority = 1;
              name = "boot";
              start = "1M";
              end = "2M";
              type = "EF02"; # BIOS boot partition
            };
            root = {
              size = "100%";
              content = {
                type = "btrfs";
                extraArgs = ["-f"]; # Override existing partition
                # Subvolumes must set a mountpoint in order to be mounted,
                # unless their parent is mounted
                subvolumes = {
                  "/root" = {
                    mountpoint = "/";
                    mountOptions = [
                      "compress=zstd"
                      "noatime"
                    ];
                  };
                  "/nix" = {
                    mountpoint = "/nix";
                    mountOptions = [
                      "compress=zstd"
                      "noatime"
                    ];
                  };
                  "/swap" = lib.mkIf withSwap {
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
}
