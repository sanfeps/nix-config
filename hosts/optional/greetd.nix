{ config, lib, pkgs, ... }:

let
  swayKiosk = command: "${lib.getExe pkgs.sway} --unsupported-gpu --config ${pkgs.writeText "kiosk.config" ''
    output * bg #000000 solid_color
    xwayland disable
    exec ${command}; ${pkgs.sway}/bin/swaymsg exit
  ''}";
in {
  users.extraUsers.greeter = {
    isSystemUser = true;
    home = "/tmp/greeter-home";
    createHome = true;
  };

  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        user = "greeter";
        command = swayKiosk (lib.getExe config.programs.regreet.package);
      };
    };
  };

  programs.regreet.enable = true;
}

