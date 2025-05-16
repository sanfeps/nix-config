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
  vars = ''XDG_DATA_DIRS="$XDG_DATA_DIRS:${lib.concatStringsSep ":" homeSharePaths}" GTK_USE_PORTAL=0 SESSION_DIRS=$SESSION_DIRS:/home/sanfe/.nix-profile/share/wayland-sessions:/home/sanfe/.local/state/nix/profiles/profile/share/wayland-sessions'';

  sway-kiosk = command: "${lib.getExe pkgs.sway} --unsupported-gpu --config ${pkgs.writeText "kiosk.config" ''
    output * bg #000000 solid_color
    xwayland disable
    input "type:touchpad" {
      tap enabled
    }
    exec '${vars} ${command}; ${pkgs.sway}/bin/swaymsg exit'
  ''}";
in {
  # users.extraUsers.greeter = {
  #   # For caching and such
  #   home = "/var/lib/greeter-home";
  #   createHome = true;
  # };

  services.displayManager.ly.enable = true;

  environment.etc."ly/config.ini".text = lib.mkForce ''
    waylandsessions = /home/sanfe/.nix-profile/share/wayland-sessions

    asterisk = 0x2022

    # The number of failed authentications before a special animation is played... ;)
    auth_fails = 10

    # Background color id
    bg = 0x00000000

    # Blank main box background
    # Setting to false will make it transparent
    blank_box = true

    # Border foreground color id
    border_fg = 0x00FFFFFF

    # Title to show at the top of the main box
    # If set to null, none will be shown
    box_title = null

    # Erase password input on failure
    clear_password = true

    # Console path
    console_dev = /dev/console

    # Input box active by default on startup
    # Available inputs: info_line, session, login, password
    default_input = login

    # Error background color id
    error_bg = 0x00000000

    # Error foreground color id
    # Default is red and bold
    error_fg = 0x01FF0000

    # Foreground color id
    fg = 0x00FFFFFF

    # Remove main box borders
    hide_borders = false

  '';

  # programs.regreet = {
  #   enable = true;
  # };
  # services.greetd = {
  #   enable = true;
  #   settings.default_session.command = sway-kiosk (lib.getExe config.programs.regreet.package);
  # };

  environment.persistence."/persist" = {
    directories = [
      { directory = "/var/lib/greeter-home"; }
    ];
  };
  environment.variables.SESSION_DIRS = "/home/sanfe/.nix-profile/share/wayland-sessions:/home/sanfe/.local/state/nix/profiles/profile/share/wayland-sessions";
}


