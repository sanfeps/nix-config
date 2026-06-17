# Fluxer desktop app (Discord alternative) — for our self-hosted instance
# (hosts/asgard/services/fluxer/, https://fluxer.lan.valgrindr.net).
#
# We deliberately do NOT use the upstream Electron client:
#   - the `stable` AppImage (v0.0.8) has no self-host support and hard-loads
#     web.fluxer.app;
#   - the `canary` AppImage DOES accept --fluxer-app-url, but its desktop bridge
#     is incompatible with our stable (`v1`) server build, so the web app's
#     bootstrap fails ("failed to start properly").
# The web client itself works perfectly against our instance, so we run it as a
# standalone app via Chromium's --app mode: a dedicated, chromeless window with
# its own profile and WM class — effectively a native-feeling desktop app, and
# immune to the Electron-shell/server version coupling above.
#
# If/when the stable AppImage gains working self-host support, this can be
# swapped back to an appimageTools wrap.
{pkgs, ...}: let
  instanceUrl = "https://fluxer.lan.valgrindr.net";
  # Dedicated Chromium profile so this app window is isolated from any other
  # browser and its login persists (see home.persistence below).
  profileDir = ".local/share/fluxer-app";
  wmClass = "fluxer";

  fluxer = pkgs.writeShellScriptBin "fluxer" ''
    exec ${pkgs.chromium}/bin/chromium \
      --app=${instanceUrl} \
      --class=${wmClass} --name=${wmClass} \
      --ozone-platform-hint=auto \
      --user-data-dir="''${XDG_DATA_HOME:-$HOME/.local/share}/fluxer-app" \
      "$@"
  '';
in {
  home.packages = [fluxer];

  xdg.desktopEntries.fluxer = {
    name = "Fluxer";
    genericName = "Chat";
    comment = "Self-hosted Fluxer (Discord alternative)";
    exec = "fluxer %U";
    icon = "${./fluxer.png}";
    terminal = false;
    type = "Application";
    categories = ["Network" "InstantMessaging"];
    # Match Chromium's --class so niri associates the window with this entry
    # (correct icon + grouping).
    settings.StartupWMClass = wmClass;
  };

  # Persist the dedicated Chromium profile (login/session) across midgard's
  # wipe-on-boot rootfs.
  home.persistence."/persist".directories = [profileDir];
}
