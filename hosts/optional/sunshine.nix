{
  config,
  pkgs,
  lib,
  ...
}: let
  monitor = lib.head (lib.filter (m: m.primary) config.home-manager.users.sanfe.monitors);
  steamRefreshRate = lib.min monitor.refreshRate 120;
  steamRenderWidth = monitor.width * 3 / 4;
  steamRenderHeight = monitor.height * 3 / 4;
  steam = "/run/current-system/sw/bin/steam";
  gamescope = "${pkgs.gamescope}/bin/gamescope";
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
    # Keep Big Picture inside gamescope and force CEF onto the GPU.
    exec ${pkgs.util-linux}/bin/setsid ${gamescope} \
      -f \
      -W ${toString monitor.width} \
      -H ${toString monitor.height} \
      -w ${toString steamRenderWidth} \
      -h ${toString steamRenderHeight} \
      -S fit \
      -F nis \
      --sharpness 10 \
      -r ${toString steamRefreshRate} \
      --adaptive-sync \
      --expose-wayland \
      --steam \
      -- ${steam} -cef-force-gpu -tenfoot -pipewire-dmabuf
  '';
  closeSteamBigPicture = pkgs.writeShellScript "sunshine-steam-big-picture-close" ''
    set -eu
    cd "$HOME"
    exec ${pkgs.util-linux}/bin/setsid ${steam} steam://close/bigpicture
  '';
in {
  services.sunshine = {
    enable = true;
    # Starting Sunshine during login races Niri for DRM/KMS on NVIDIA.
    # Keep it installed, but start it on demand from a running session.
    autoStart = false;
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
