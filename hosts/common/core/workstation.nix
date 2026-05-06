# This file holds workstation-specific config that should not land on servers.
{pkgs, ...}: {
  imports = [
    ./pipewire.nix
    ./rpcbind.nix
    ./mullvad-vpn.nix
  ];

  # Udev rules for local development hardware.
  services.udev.packages = with pkgs; [
    platformio-core
    openocd
  ];
}
