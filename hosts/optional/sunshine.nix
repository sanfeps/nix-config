{
  config,
  pkgs,
  ...
}: let
  steam = "${config.programs.steam.package}/bin/steam";
  steamIcon = "${config.programs.steam.package}/share/icons/hicolor/256x256/apps/steam.png";
  setsid = "${pkgs.util-linux}/bin/setsid";
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
            "${setsid} ${steam} steam://open/bigpicture"
          ];
          prep-cmd = [
            {
              do = "${pkgs.coreutils}/bin/true";
              undo = "${setsid} ${steam} steam://close/bigpicture";
            }
          ];
          auto-detach = true;
          image-path = steamIcon;
        }
      ];
    };
  };
}
