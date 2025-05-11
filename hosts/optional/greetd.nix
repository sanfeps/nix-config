{
  config,
  pkgs,
  lib,
  ...
}:
{
  config = {
    #    environment.systemPackages = [ pkgs.greetd.tuigreet ];
    services.greetd = {
      enable = true;

      restart = true;
      settings = {
        default_session = {
          command = "${pkgs.greetd.tuigreet}/bin/tuigreet --asterisks --time --time-format '%I:%M %p | %a • %h | %F' --cmd Hyprland";
          user = "sanfe";
        };
      };
    };
  };
}

