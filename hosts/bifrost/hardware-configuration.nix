# Cloned verbatim from asgard's hardware-configuration.nix — both bifrost and
# asgard are Proxmox VMs with the same virtio-scsi disk + qemu-guest profile.
# If anything Proxmox-side differs (NIC type, disk controller swap, etc.) just
# regenerate this file with `nixos-generate-config --show-hardware-config`.
{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}: {
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  boot.initrd.availableKernelModules = ["ata_piix" "uhci_hcd" "virtio_pci" "virtio_scsi" "sd_mod" "sr_mod"];
  boot.initrd.kernelModules = [];
  boot.kernelModules = [];
  boot.extraModulePackages = [];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
