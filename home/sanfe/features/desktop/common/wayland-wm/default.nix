{
  pkgs,
  config,
  ...
}: {
  imports = [
    ./alacritty.nix
    ./wofi.nix
    ./quickshell/quickshell.nix
    ./vscode.nix
  ];

  home.packages = with pkgs; [
    librewolf
    remmina
  ];

  home.sessionVariables = {
    MOZ_ENABLE_WAYLAND = 1;
    QT_QPA_PLATFORM = "wayland";
    LIBSEAT_BACKEND = "logind";
  };

  home.persistence = {
    "/persist" = {
      directories = [
        ".librewolf"
        ".mozilla"
        ".config/remmina"
        ".local/share/remmina"
      ];
    };
  };
}
