{config, ...}: let
  cfg = config.services.mosquitto;
in {
  services.mosquitto = {
    enable = true;

    listeners = [
      {
        port = 1883;
        address = "127.0.0.1";
        omitPasswordAuth = true;
        settings.allow_anonymous = true;
      }
    ];
  };

  environment.persistence."/persist".directories = [
    {
      directory = cfg.dataDir;
      user = "mosquitto";
      group = "mosquitto";
      mode = "0750";
    }
  ];
}
