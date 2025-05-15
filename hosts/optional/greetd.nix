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

    # Allow empty password or not when authenticating
allow_empty_password = true

# The active animation
# none     -> Nothing
# doom     -> PSX DOOM fire
# matrix   -> CMatrix
# colormix -> Color mixing shader
animation = none

# Stop the animation after some time
# 0 -> Run forever
# 1..2e12 -> Stop the animation after this many seconds
animation_timeout_sec = 0

# The character used to mask the password
# You can either type it directly as a UTF-8 character (like *), or use a UTF-32
# codepoint (for example 0x2022 for a bullet point)
# If null, the password will be hidden
# Note: you can use a # by escaping it like so: \#
asterisk = *

# The number of failed authentications before a special animation is played... ;)
auth_fails = 10

# Background color id
bg = 0x00000000

# Change the state and language of the big clock
# none -> Disabled (default)
# en   -> English
# fa   -> Farsi
bigclock = none

# Blank main box background
# Setting to false will make it transparent
blank_box = true

# Border foreground color id
border_fg = 0x00FFFFFF

# Title to show at the top of the main box
# If set to null, none will be shown
box_title = null

# Brightness increase command
brightness_down_cmd = $PREFIX_DIRECTORY/bin/brightnessctl -q s 10%-

# Brightness decrease key, or null to disable
brightness_down_key = F5

# Brightness increase command
brightness_up_cmd = $PREFIX_DIRECTORY/bin/brightnessctl -q s +10%

# Brightness increase key, or null to disable
brightness_up_key = F6

# Erase password input on failure
clear_password = false

# Format string for clock in top right corner (see strftime specification). Example: %c
# If null, the clock won't be shown
clock = null

# CMatrix animation foreground color id
cmatrix_fg = 0x0000FF00

# CMatrix animation minimum codepoint. It uses a 16-bit integer
# For Japanese characters for example, you can use 0x3000 here
cmatrix_min_codepoint = 0x21

# CMatrix animation maximum codepoint. It uses a 16-bit integer
# For Japanese characters for example, you can use 0x30FF here
cmatrix_max_codepoint = 0x7B

# Color mixing animation first color id
colormix_col1 = 0x00FF0000

# Color mixing animation second color id
colormix_col2 = 0x000000FF

# Color mixing animation third color id
colormix_col3 = 0x20000000

# Console path
console_dev = /dev/console

# Input box active by default on startup
# Available inputs: info_line, session, login, password
default_input = login

# DOOM animation top color (low intensity flames)
doom_top_color = 0x00FF0000

# DOOM animation middle color (medium intensity flames)
doom_middle_color = 0x00FFFF00

# DOOM animation bottom color (high intensity flames)
doom_bottom_color = 0x00FFFFFF

# Error background color id
error_bg = 0x00000000

# Error foreground color id
# Default is red and bold
error_fg = 0x01FF0000

# Foreground color id
fg = 0x00FFFFFF

# Remove main box borders
hide_borders = false

# Remove power management command hints
hide_key_hints = false

# Initial text to show on the info line
# If set to null, the info line defaults to the hostname
initial_info_text = null

# Input boxes length
input_len = 34

# Active language
# Available languages are found in $CONFIG_DIRECTORY/ly/lang/
lang = en

# Load the saved desktop and username
load = true

# Command executed when logging in
# If null, no command will be executed
# Important: the code itself must end with `exec "$@"` in order to launch the session!
# You can also set environment variables in there, they'll persist until logout
login_cmd = null

# Command executed when logging out
# If null, no command will be executed
# Important: the session will already be terminated when this command is executed, so
# no need to add `exec "$@"` at the end
logout_cmd = null

# Main box horizontal margin
margin_box_h = 2

# Main box vertical margin
margin_box_v = 1

# Event timeout in milliseconds
min_refresh_delta = 5

# Set numlock on/off at startup
numlock = false

# Default path
# If null, ly doesn't set a path
path = /sbin:/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin

# Command executed when pressing restart_key
restart_cmd = /sbin/shutdown -r now

# Specifies the key used for restart (F1-F12)
restart_key = F2

# Save the current desktop and login as defaults
save = true

# Service name (set to ly to use the provided pam config file)
service_name = ly

# Session log file path
# This will contain stdout and stderr of Wayland sessions
# By default it's saved in the user's home directory
# Important: due to technical limitations, X11 and shell sessions aren't supported, which
# means you won't get any logs from those sessions
session_log = ly-session.log

# Setup command
setup_cmd = $CONFIG_DIRECTORY/ly/setup.sh

# Command executed when pressing shutdown_key
shutdown_cmd = /sbin/shutdown -a now

# Specifies the key used for shutdown (F1-F12)
shutdown_key = F1

# Command executed when pressing sleep key (can be null)
sleep_cmd = null

# Specifies the key used for sleep (F1-F12)
sleep_key = F3

# Center the session name.
text_in_center = false

# TTY in use
tty = $DEFAULT_TTY

# Default vi mode
# normal   -> normal mode
# insert   -> insert mode
vi_default_mode = normal

# Enable vi keybindings
vi_mode = false

# Wayland desktop environments
# You can specify multiple directories,
# e.g. /usr/share/wayland-sessions:/usr/local/share/wayland-sessions

# Xorg server command
x_cmd = $PREFIX_DIRECTORY/bin/X

# Xorg xauthority edition tool
xauth_cmd = $PREFIX_DIRECTORY/bin/xauth

# xinitrc
# If null, the xinitrc session will be hidden
xinitrc = ~/.xinitrc

# Xorg desktop environments
# You can specify multiple directories,
# e.g. /usr/share/xsessions:/usr/local/share/xsessions
xsessions = $PREFIX_DIRECTORY/share/xsessions
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


