{
  pkgs,
  config,
  ...
}: {
  imports = [
    ./alacritty.nix
    ./ghostty.nix
    ./wofi.nix
    # ./quickshell/quickshell.nix  # WIP custom shell, disabled in favor of noctalia
    ./noctalia.nix
    ./vscode.nix
  ];

  home.packages = with pkgs; [
    librewolf
    remmina
    vesktop
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
