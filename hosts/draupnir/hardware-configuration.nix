# Hand-written (nixos-anywhere install; no nixos-generate-config run yet).
# UGREEN NASync DXP4800 Plus: Intel Pentium Gold 8505 (Alder Lake-N family),
# NVMe OS disk + 4x SATA bays behind AHCI.
{
  config,
  lib,
  ...
}: {
  boot.initrd.availableKernelModules = ["xhci_pci" "ahci" "nvme" "usb_storage" "usbhid" "sd_mod"];
  boot.initrd.kernelModules = [];
  boot.kernelModules = ["kvm-intel"];
  boot.extraModulePackages = [];

  # NIC (Realtek 2.5GbE / Aquantia 10GbE) and iGPU firmware blobs.
  hardware.enableRedistributableFirmware = true;
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
