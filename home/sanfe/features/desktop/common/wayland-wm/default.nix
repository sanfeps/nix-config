{pkgs, ...}: {
  imports = [
    ./alacritty.nix
    ./wofi.nix
    ./quickshell/quickshell.nix
    ./vscode.nix
  ];

  home.packages = with pkgs; [
	librewolf
  ];

  home.sessionVariables = {
    MOZ_ENABLE_WAYLAND = 1;
    QT_QPA_PLATFORM = "wayland";
    LIBSEAT_BACKEND = "logind";
  };

  xdg.portal.extraPortals = [pkgs.xdg-desktop-portal-wlr];
}
