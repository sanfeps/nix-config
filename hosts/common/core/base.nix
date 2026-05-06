# This file holds the minimal base config shared by all hosts.
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
      ./sops.nix
      ./zsh.nix
      ./optin-persistence.nix
      ../../../modules/common/host-spec.nix
    ]
    ++ (builtins.attrValues outputs.nixosModules);

  home-manager.useGlobalPkgs = true;
  home-manager.backupFileExtension = "hm-backup";
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

  services.speechd.enable = lib.mkForce false;

  environment.systemPackages = with pkgs; [
    git
    ghostty.terminfo
    vim
  ];
}
