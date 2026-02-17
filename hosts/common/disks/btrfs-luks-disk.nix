# NOTE: ... is needed because dikso passes diskoFile
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
                name = "encrypted-root";
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
}
