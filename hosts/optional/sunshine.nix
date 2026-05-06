{
  services.sunshine = {
    enable = true;
    autoStart = true;
    capSysAdmin = true;
    openFirewall = true;
    applications = {
      env = {
        PATH = "$(PATH):$(HOME)/.local/bin";
      };
      apps = [
        {
          name = "Steam Big Picture";
          prep-cmd = [
            {
              do = "steam steam://open/bigpicture";
              undo = "steam steam://close/bigpicture";
            }
          ];
          image-path = "steam.png";
        }
      ];
    };
  };
}
