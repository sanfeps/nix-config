{
  config,
  lib,
  ...
}: let
  cfg = config.services.home-assistant;
in {
  services.home-assistant = {
    enable = true;
    # openFirewall would expose :8123 to the whole LAN. Bifrost (the edge)
    # is the only off-host client that should reach it; firewall rule below.
    openFirewall = false;

    config = {
      default_config = {};

      frontend = {
        themes = "!include_dir_merge_named themes";
      };

      homeassistant = {
        name = "Asgard";
        time_zone = config.time.timeZone;
        unit_system = "metric";
        packages = "!include_dir_named packages";
      };

      http = {
        use_x_forwarded_for = true;
        # bifrost terminates TLS and forwards X-Forwarded-For. Trust the LAN
        # source it proxies from so client IPs are surfaced correctly in HA.
        trusted_proxies = [
          "127.0.0.1"
          "::1"
          "192.168.1.55"
        ];
      };

      mqtt = {
        broker = "127.0.0.1";
        port = 1883;
      };

      recorder = {
        auto_purge = true;
        purge_keep_days = 14;
      };

      "automation nix" = [];
      "automation ui" = "!include automations.yaml";

      "scene nix" = [];
      "scene ui" = "!include scenes.yaml";

      "script nix" = {};
      "script ui" = "!include scripts.yaml";
    };
  };

  systemd.services.home-assistant.preStart = lib.mkAfter ''
    mkdir -p "${cfg.configDir}/packages" "${cfg.configDir}/themes" "${cfg.configDir}/www"

    if [ ! -e "${cfg.configDir}/automations.yaml" ]; then
      printf '[]\n' > "${cfg.configDir}/automations.yaml"
    fi

    if [ ! -e "${cfg.configDir}/scenes.yaml" ]; then
      printf '[]\n' > "${cfg.configDir}/scenes.yaml"
    fi

    if [ ! -e "${cfg.configDir}/scripts.yaml" ]; then
      printf '{}\n' > "${cfg.configDir}/scripts.yaml"
    fi

    if [ ! -e "${cfg.configDir}/secrets.yaml" ]; then
      printf '{}\n' > "${cfg.configDir}/secrets.yaml"
    fi
  '';

  environment.persistence."/persist".directories = [
    {
      directory = cfg.configDir;
      user = "hass";
      group = "hass";
      mode = "0750";
    }
  ];

  # Only bifrost reaches :8123 from off-host; everyone else gets the cert via
  # the bifrost edge. iptables sintax — asgard still runs the legacy backend.
  networking.firewall.extraCommands = ''
    iptables -I nixos-fw -p tcp --dport 8123 -s 192.168.1.55 -j nixos-fw-accept
  '';
}
