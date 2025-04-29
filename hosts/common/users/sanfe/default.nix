{
  pkgs,
  config,
  lib,
  ...
}: let
  ifTheyExist = groups: builtins.filter (group: builtins.hasAttr group config.users.groups) groups;
in {
  users.mutableUsers = true;
  users.users.sanfe = {
    isNormalUser = true;
    shell = pkgs.zsh;
    extraGroups = ifTheyExist [
      "audio"
      "git"
      "i2c"
      "libvirtd"
      "network"
      "podman"
      "video"
      "wheel"
      "wireshark"
    ];

    openssh.authorizedKeys.keys = lib.splitString "\n" (builtins.readFile ../../../../home/sanfe/ssh.pub);
    initialPassword = "sanfe";
    packages = [pkgs.home-manager];
  };

  sops.secrets.sanfe-password = {
    sopsFile = ../../secrets.yaml;
    neededForUsers = true;
  };

  # home-manager.users.sanfe = import ../../../../home/sanfe/${config.networking.hostName}.nix;

  # security.pam.services = {
    # swaylock = {};
  # };
}
