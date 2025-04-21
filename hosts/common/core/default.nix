# This file (and the core directory) holds config that i use on all hosts
{
  inputs,
  outputs,
  ...
}: {
  imports =
    [
      inputs.home-manager.nixosModules.home-manager
      ./locale.nix
      ./nix.nix
      ./openssh.nix
      # ./podman.nix
      ./sops.nix
      ./zsh.nix
      # ./steam-hardware.nix
      # ./systemd-initrd.nix
      # ./gamemode.nix
      # ./nix-ld.nix
      # ./prometheus-node-exporter.nix
      # ./kdeconnect.nix
    ]
    ++ (builtins.attrValues outputs.nixosModules);

  home-manager.useGlobalPkgs = true;
  home-manager.extraSpecialArgs = {
    inherit inputs outputs;
  };

  nixpkgs = {
    overlays = builtins.attrValues outputs.overlays;
    config = {
      allowUnfree = true;
    };
  };

  hardware.enableRedistributableFirmware = true;
  networking.domain = "sfg.lo";

  # Cleanup stuff included by default
  services.speechd.enable = false;
}
