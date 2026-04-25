{
  pkgs,
  lib,
  ...
}: {
  imports = [
    ../common
    ../common/wayland-wm
  ];

  home.packages = [pkgs.niri pkgs.awww pkgs.xwayland-satellite];

  xdg.portal = {
    extraPortals = [pkgs.xdg-desktop-portal-gtk pkgs.xdg-desktop-portal-gnome];
    config.niri = {
      default = ["gtk"];
      "org.freedesktop.impl.portal.ScreenCast" = ["gnome"];
      "org.freedesktop.impl.portal.Screenshot" = ["gnome"];
      "org.freedesktop.impl.portal.RemoteDesktop" = ["gnome"];
    };
  };

  xdg.configFile."niri/config.kdl".source = ./config.kdl;
}
