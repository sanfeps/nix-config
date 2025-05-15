{
  pkgs,
  lib,
  config,
  ...
}: let
  homeCfgs = config.home-manager.users;
  #homeSharePaths = lib.mapAttrsToList (_: v: "${v.home.path}/share") homeCfgs;
  homeSharePaths = lib.flatten [
    (lib.mapAttrsToList (_: v: "${v.home.path}/share") homeCfgs)
    "/home/sanfe/.nix-profile/share/wayland-sessions"
    "/home/sanfe/.local/state/nix/profiles/profile/share/wayland-sessions"
  ];
  vars = ''XDG_DATA_DIRS="$XDG_DATA_DIRS:${lib.concatStringsSep ":" homeSharePaths}" GTK_USE_PORTAL=0'';

  sway-kiosk = command: "${lib.getExe pkgs.sway} --unsupported-gpu --config ${pkgs.writeText "kiosk.config" ''
    output * bg #000000 solid_color
    xwayland disable
    input "type:touchpad" {
      tap enabled
    }
    exec '${vars} ${command}; ${pkgs.sway}/bin/swaymsg exit'
  ''}";
in {
  users.extraUsers.greeter = {
    # For caching and such
    home = "/var/lib/greeter-home";
    createHome = true;
  };

  programs.regreet = {
    enable = true;
    settings = {
      cache_directory = "/var/lib/greeter-home/.cache/regreet";
    };
  };
  services.greetd = {
    enable = true;
    settings.default_session.command = sway-kiosk (lib.getExe config.programs.regreet.package);
  };

  environment.persistence."/persist" = {
    directories = [
      { directory = "/var/lib/greeter-home"; }
    ];
  };

  environment.etc."wayland-sessions/hyprland.desktop".text = ''
  [Desktop Entry]
  Name=Hyprland
  Comment=Hyprland Wayland Compositor
  Exec=Hyprland
  Type=Application
'';

  programs.hyprland.enable = true;

}


