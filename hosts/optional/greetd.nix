{ config, lib, pkgs, ... }:

let
  swayKiosk = command: "${lib.getExe pkgs.sway} --unsupported-gpu --config ${pkgs.writeText "kiosk.config" ''
    output * bg #000000 solid_color
    xwayland disable
    exec ${command}; ${pkgs.sway}/bin/swaymsg exit
  ''}";
in {
  # Usuario temporal para ejecutar la pantalla de login
  users.extraUsers.greeter = {
    isSystemUser = true;
    home = "/tmp/greeter-home";
    createHome = true;
  };

  # Activar greetd y usar sway + regreet como pantalla de login
  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        user = "greeter";
        command = swayKiosk (lib.getExe pkgs.regreet);
      };
    };
  };

  # Habilitar regreet sin configuración personalizada
  programs.regreet.enable = true;
}

