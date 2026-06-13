{...}: {
  # Service contract (behind-Caddy http block, first-boot seeding, include-dir
  # scaffolding, persistence, the local-Caddy vhost) lives in the reusable
  # module `modules/homelab/services/home-assistant`. This file only enables it
  # and supplies asgard-specific config: the instance name and the co-located
  # Mosquitto broker (see ./mosquitto.nix).
  homelab.services.homeAssistant = {
    enable = true;
    url = "home.lan.valgrindr.net";
    name = "Asgard";
    extraConfig = {
      mqtt = {
        broker = "127.0.0.1";
        port = 1883;
      };
    };
  };
}
