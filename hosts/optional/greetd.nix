{
  pkgs,
  lib,
  config,
  ...
}: let
  homeCfgs = config.home-manager.users;
  homeSharePaths = lib.mapAttrsToList (_: v: "${v.home.path}/share") homeCfgs;
in {
  services.displayManager.ly = {
    enable = true;
    settings = {
	waylandsessions = "${lib.concatStringsSep ":" homeSharePaths}/wayland-sessions";
	xsessions = "${lib.concatStringsSep ":" homeSharePaths}/xsessions";
    };
  };  

  environment.persistence = {
    "${config.hostSpec.persistFolder}" = {
      files = [
        "/etc/ly/save.ini"
      ];
    };
  };
}


