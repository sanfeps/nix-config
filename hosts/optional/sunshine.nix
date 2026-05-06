{
  config,
  pkgs,
  ...
}: let
  steam = "/run/current-system/sw/bin/steam";
  steamIcon = "${config.programs.steam.package}/share/icons/hicolor/256x256/apps/steam.png";
  launchSteamBigPicture = pkgs.writeShellScript "sunshine-steam-big-picture" ''
    set -eu
    cd "$HOME"
    {
      echo "[$(${pkgs.coreutils}/bin/date --iso-8601=seconds)] launch"
      echo "PWD=$PWD"
      echo "DISPLAY=$DISPLAY"
      echo "WAYLAND_DISPLAY=$WAYLAND_DISPLAY"
      echo "DBUS_SESSION_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS"
      echo "XDG_CURRENT_DESKTOP=$XDG_CURRENT_DESKTOP"
    } >> /tmp/sunshine-steam-big-picture.log
    exec ${pkgs.util-linux}/bin/setsid ${steam} steam://open/bigpicture
  '';
  closeSteamBigPicture = pkgs.writeShellScript "sunshine-steam-big-picture-close" ''
    set -eu
    cd "$HOME"
    exec ${pkgs.util-linux}/bin/setsid ${steam} steam://close/bigpicture
  '';
in {
  services.sunshine = {
    enable = true;
    autoStart = true;
    openFirewall = true;
    settings.min_log_level = 1;
    applications = {
      apps = [
        {
          name = "Steam Big Picture";
          detached = [
            launchSteamBigPicture
          ];
          prep-cmd = [
            {
              do = "${pkgs.coreutils}/bin/true";
              undo = closeSteamBigPicture;
            }
          ];
          auto-detach = true;
          image-path = steamIcon;
        }
      ];
    };
  };

  systemd.user.services.sunshine.serviceConfig.Environment = [
    "LD_LIBRARY_PATH=/run/opengl-driver/lib:/run/opengl-driver-32/lib"
  ];
}
