{
  pkgs,
  lib,
  config,
  ...
}: let
  monitor = lib.head (lib.filter (m: m.primary) config.monitors);
  steamRefreshRate = lib.min monitor.refreshRate 120;
  steamRenderWidth = monitor.width * 3 / 4;
  steamRenderHeight = monitor.height * 3 / 4;
  steamExe = "/run/current-system/sw/bin/steam";
  steam-session = let
    gamescope = lib.concatStringsSep " " [
      (lib.getExe pkgs.gamescope)
      "--output-width ${toString monitor.width}"
      "--output-height ${toString monitor.height}"
      "--nested-width ${toString steamRenderWidth}"
      "--nested-height ${toString steamRenderHeight}"
      "--scaler fit"
      "--filter nis"
      "--sharpness 10"
      "--nested-refresh ${toString steamRefreshRate}"
      "--prefer-output ${monitor.name}"
      "--adaptive-sync"
      "--expose-wayland"
      "--steam"
    ];
    steam = lib.concatStringsSep " " [
      steamExe
      "-cef-force-gpu"
      "-tenfoot"
      "-pipewire-dmabuf"
    ];
  in
    pkgs.writeTextDir "share/wayland-sessions/steam-session.desktop" # ini
    
    ''
      [Desktop Entry]
      Name=Steam Session
      Exec=${gamescope} -- ${steam}
      Type=Application
    '';
in {
  home.packages = [
    steam-session
    pkgs.gamescope
    pkgs.protontricks
  ];
  home.persistence = {
    "/persist" = {
      directories = [
        ".local/share/Steam"
        ".steam"
        ".cache/nvidia"
      ];
    };
  };
}
