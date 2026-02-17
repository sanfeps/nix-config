{
  pkgs,
  lib,
  ...
}: {
  imports = [
    ../common
    ../common/wayland-wm
  ];

  home.packages = [pkgs.niri];

  xdg.portal = {
    extraPortals = [pkgs.xdg-desktop-portal-gtk];
    config.niri = {
      default = ["gtk"];
    };
  };

  xdg.configFile."niri/config.kdl".source = ./config.kdl;
}
