# This file (and the core directory) holds config that i use on all hosts
{
  inputs,
  outputs,
  pkgs,
  lib,
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
      ./optin-persistence.nix
      ./mullvad-vpn.nix
      # ./steam-hardware.nix
      # ./systemd-initrd.nix
      # ./gamemode.nix
      # ./nix-ld.nix
      # ./prometheus-node-exporter.nix
      # ./kdeconnect.nix
      ../../../modules/common/host-spec.nix
    ]
    ++ (builtins.attrValues outputs.nixosModules);

  home-manager.useGlobalPkgs = true;
  home-manager.extraSpecialArgs = {
    inherit inputs outputs;
  };

  hostSpec = {
    username = "sanfe";
    persistFolder = "/persist";
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
  services.speechd.enable = lib.mkForce false;

  # System packages
  environment.systemPackages = with pkgs; [

    git
    vim

  ];
}
