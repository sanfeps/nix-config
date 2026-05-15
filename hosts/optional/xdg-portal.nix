# System-level xdg-desktop-portal setup. Required because niri is installed as
# a plain home-manager package rather than via `programs.niri.enable`, so no
# NixOS module wires up the portal services automatically (unlike how
# `programs.hyprland.enable` did before). Without this, screen-share in
# Electron apps like Vesktop has no portal backend to talk to.
# `config.common` is used so the routing applies to any compositor.
{pkgs, ...}: {
  xdg.portal = {
    enable = true;
    extraPortals = [
      pkgs.xdg-desktop-portal-gtk
      pkgs.xdg-desktop-portal-gnome
    ];
    config.common = {
      default = ["gtk"];
      "org.freedesktop.impl.portal.ScreenCast" = ["gnome"];
      "org.freedesktop.impl.portal.Screenshot" = ["gnome"];
      "org.freedesktop.impl.portal.RemoteDesktop" = ["gnome"];
    };
  };
}
