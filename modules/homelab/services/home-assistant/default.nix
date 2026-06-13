{
  config,
  lib,
  ...
}:
# Home Assistant as a reusable homelab service.
#
# Thin wrapper (see docs/services-reusable-modules-plan.md): the module owns
# the parts that repeat across any host fronting HA with a local Caddy — the
# behind-Caddy `http` block, the first-boot `!include`-target seeding, the
# include-dir scaffolding, and configDir persistence — and exposes the few
# knobs a host varies. Everything domain-specific (mqtt broker, integrations,
# custom packages) goes through `extraConfig`, which deep-merges over the
# baseline; or drop into `services.home-assistant.*` directly.
with lib; let
  cfg = config.homelab.services.homeAssistant;
  haCfg = config.services.home-assistant;
in {
  options.homelab.services.homeAssistant = {
    enable = mkEnableOption "Home Assistant (behind the host's local Caddy)";

    url = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "home.lan.valgrindr.net";
      description = ''
        FQDN to front Home Assistant with on the host's local Caddy. When
        non-null a `services.caddy.virtualHosts.<url>` reverse-proxy to the HA
        listener is declared — requires a Caddy on the host (e.g.
        `services.caddyNjalla.enable`). Null = backend only, no vhost.
      '';
    };

    port = mkOption {
      type = types.port;
      default = 8123;
      description = "Port HA's HTTP server binds to on loopback (also the Caddy reverse-proxy target).";
    };

    name = mkOption {
      type = types.str;
      example = "Asgard";
      description = "Friendly name for this Home Assistant instance.";
    };

    extraConfig = mkOption {
      type = types.attrs;
      default = {};
      example = literalExpression ''{ mqtt = { broker = "127.0.0.1"; port = 1883; }; }'';
      description = ''
        Deep-merged (via `lib.recursiveUpdate`) into `services.home-assistant.config`
        on top of the module baseline (default_config, frontend themes, the
        behind-Caddy http block, recorder defaults, and the nix/ui
        automation-scene-script split). Host-specific domains go here; leaf
        values override the baseline.
      '';
    };
  };

  config = mkIf cfg.enable {
    services.home-assistant = {
      enable = true;
      openFirewall = false; # fronted by the local Caddy on loopback.

      config =
        recursiveUpdate {
          default_config = {};

          frontend.themes = "!include_dir_merge_named themes";

          homeassistant = {
            name = cfg.name;
            time_zone = config.time.timeZone;
            unit_system = "metric";
            packages = "!include_dir_named packages";
          };

          # Behind the host's local Caddy on loopback — trust only the loopback
          # hop, no cross-host proxy.
          http = {
            server_host = "127.0.0.1";
            server_port = cfg.port;
            use_x_forwarded_for = true;
            trusted_proxies = [
              "127.0.0.1"
              "::1"
            ];
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
        }
        cfg.extraConfig;
    };

    # Front HA with the host's local Caddy when a url is given.
    services.caddy.virtualHosts = mkIf (cfg.url != null) {
      ${cfg.url}.extraConfig = ''
        reverse_proxy 127.0.0.1:${toString cfg.port}
      '';
    };

    # Seed the !include targets + include dirs on first boot so HA doesn't fail
    # to start before the UI has written them.
    systemd.services.home-assistant.preStart = mkAfter ''
      mkdir -p "${haCfg.configDir}/packages" "${haCfg.configDir}/themes" "${haCfg.configDir}/www"

      if [ ! -e "${haCfg.configDir}/automations.yaml" ]; then
        printf '[]\n' > "${haCfg.configDir}/automations.yaml"
      fi

      if [ ! -e "${haCfg.configDir}/scenes.yaml" ]; then
        printf '[]\n' > "${haCfg.configDir}/scenes.yaml"
      fi

      if [ ! -e "${haCfg.configDir}/scripts.yaml" ]; then
        printf '{}\n' > "${haCfg.configDir}/scripts.yaml"
      fi

      if [ ! -e "${haCfg.configDir}/secrets.yaml" ]; then
        printf '{}\n' > "${haCfg.configDir}/secrets.yaml"
      fi
    '';

    environment.persistence."${config.hostSpec.persistFolder}".directories = [
      {
        directory = haCfg.configDir;
        user = "hass";
        group = "hass";
        mode = "0750";
      }
    ];
  };
}
