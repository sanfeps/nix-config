{
  inputs,
  pkgs,
  lib,
  config,
  ...
}: let
  qs = inputs.quickshell.packages.${pkgs.system}.default;
in {
  home.packages = with pkgs; [
    qs
    qt6.qtbase
    qt6.qtwayland
    qt6.qtdeclarative
    qt6.qtsvg
    # Fonts for shell theme
    nerd-fonts.fira-mono
    rubik
    readexpro
    material-symbols
  ];

  fonts.fontconfig.enable = true;

  # Link the QuickShell configuration
  xdg.configFile."quickshell/quickshell-config".source = ./quickshell-config;

  # Autostart QuickShell with systemd user service
  systemd.user.services.quickshell = {
    Unit = {
      Description = "QuickShell - QML Desktop Shell";
      After = ["graphical-session.target"];
      PartOf = ["graphical-session.target"];
    };

    Service = {
      ExecStart = "${qs}/bin/qs -p ${config.xdg.configHome}/quickshell/quickshell-config";
      Restart = "on-failure";
      RestartSec = 3;
    };

    Install = {
      WantedBy = ["graphical-session.target"];
    };
  };
}
