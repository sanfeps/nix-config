# PLACEHOLDER — regenerate on the real box: `nixos-generate-config --no-filesystems`
# (filesystems come from disko: btrfs-disk-uefi.nix for the NVMe OS disk +
# ./disko-data.nix for the HDD `cold` pool), then replace this file with the
# generated one. The values below are a generic mini-PC guess to keep the
# module valid; every line is TODO(hw).
{
  config,
  lib,
  modulesPath,
  ...
}: {
  imports = [(modulesPath + "/installer/scan/not-detected.nix")];

  # TODO(hw): real values from nixos-generate-config on the mini-PC.
  boot.initrd.availableKernelModules = ["xhci_pci" "ahci" "nvme" "usb_storage" "sd_mod"];
  boot.initrd.kernelModules = [];
  boot.kernelModules = ["kvm-intel"]; # TODO(hw): "kvm-amd" if the CPU is AMD
  boot.extraModulePackages = [];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  # TODO(hw): enable the microcode update matching the CPU vendor.
  # hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  # hardware.cpu.amd.updateMicrocode   = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
