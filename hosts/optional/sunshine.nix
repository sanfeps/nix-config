{
  config,
  pkgs,
  ...
}: let
  steam = "${config.programs.steam.package}/bin/steam";
  steamIcon = "${config.programs.steam.package}/share/icons/hicolor/256x256/apps/steam.png";
in {
  services.sunshine = {
    enable = true;
    autoStart = true;
    capSysAdmin = true;
    openFirewall = true;
    applications = {
      apps = [
        {
          name = "Steam Big Picture";
          detached = [
            "${steam} steam://open/bigpicture"
          ];
          prep-cmd = [
            {
              do = "${pkgs.coreutils}/bin/true";
              undo = "${steam} steam://close/bigpicture";
            }
          ];
          auto-detach = true;
          image-path = steamIcon;
        }
      ];
    };
  };
}
