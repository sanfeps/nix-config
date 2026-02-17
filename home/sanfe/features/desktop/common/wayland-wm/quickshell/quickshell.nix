{
  inputs,
  pkgs,
  lib,
  config,
  ...
}: {
  home.packages = with pkgs; [
    #inputs.quickshell.packages.${pkgs.system}.default
    qt6.qtbase
    qt6.qtwayland
    qt6.qtdeclarative
    qt6.qtsvg
    # Fonts for thorn-inspired theme
    nerd-fonts.fira-code
    nerd-fonts.jetbrains-mono
    material-symbols
    # Optional: for future wallpaper management
    # walrus  # pywal alternative - uncomment when ready
  ];

  # Fonts configuration
  fonts.fontconfig.enable = true;

  #home.sessionVariables = {
  #  QML2_IMPORT_PATH = "${pkgs.qt6}/qml";
  #};

  # Link the QuickShell configuration
  xdg.configFile."quickshell/quickshell-config".source = ./quickshell-config;

  # Autostart QuickShell with systemd user service
  #systemd.user.services.quickshell = {
   # Unit = {
    #  Description = "QuickShell - Thorn-inspired QML Desktop Shell";
    #  After = ["graphical-session.target"];
    #  PartOf = ["graphical-session.target"];
    # };

    # Service = {
     # ExecStart = "${inputs.quickshell.packages.${pkgs.system}.default}/bin/quickshell -c ${config.xdg.configHome}/quickshell/quickshell-config";
     # Restart = "on-failure";
     # RestartSec = 3;
     # Environment = [
     #   "QML2_IMPORT_PATH=${pkgs.qt6}/qml"
     # ];
    #};

    #Install = {
    #  WantedBy = ["graphical-session.target"];
    #};
 # };
}
