{pkgs, ...}: {
  imports = [
    ../common
    ../common/wayland-wm
  ];

  home.packages = [pkgs.niri pkgs.awww pkgs.xwayland-satellite];

  xdg.configFile."niri/config.kdl".source = ./config.kdl;
}
