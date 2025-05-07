{pkgs, ...}: {
  imports = [
    ./alacritty.nix
    ./waybar.nix
    ./wofi.nix
  ];

  home.packages = with pkgs; [
  ];

  home.sessionVariables = {
    MOZ_ENABLE_WAYLAND = 1;
    QT_QPA_PLATFORM = "wayland";
    LIBSEAT_BACKEND = "logind";
  };

  xdg.portal.extraPortals = [pkgs.xdg-desktop-portal-wlr];
}
