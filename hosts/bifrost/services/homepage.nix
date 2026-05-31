{...}: let
  listenPort = 8082;
  virtualHost = "homepage.lan.valgrindr.net";
in {
  # homepage-dashboard — single declarative landing page for every service in
  # the cluster, regardless of which host runs it. Pattern A: listens locally
  # on bifrost, bifrost's wildcard Caddy fronts it at https://${virtualHost}.
  #
  # The whole config (tiles, groups, widgets, bookmarks) is declared in Nix and
  # rendered by the module into homepage's expected YAML files at /etc/homepage-dashboard.
  # No clicking around in a UI to add tiles — every new service should be added
  # here in the same commit that introduces it.
  services.homepage-dashboard = {
    enable = true;
    inherit listenPort;
    # Allowlist for the Host header — homepage rejects requests with a Host it
    # doesn't recognise (Host-header attack mitigation). Caddy strips/passes
    # the original Host so this needs to match the public-facing name.
    allowedHosts = virtualHost;
    # No openFirewall: only Caddy on this same host reaches :8082 via 127.0.0.1.

    settings = {
      title = "valgrindr";
      theme = "dark";
      headerStyle = "clean";
      # Hide the homepage version/footer once we're happy with the layout.
      hideVersion = true;
    };

    # Two columns: one per host role. Add a new entry every time a new service
    # lands in the flake, so the dashboard stays in lockstep with the topology.
    services = [
      {
        "Edge (bifrost)" = [
          {
            "AdGuard Home" = {
              href = "https://adguard.lan.valgrindr.net";
              description = "LAN DNS + ad blocking";
              icon = "adguard-home.png";
            };
          }
          {
            "Headplane" = {
              href = "https://headplane.lan.valgrindr.net/admin";
              description = "Headscale admin UI (nodes, ACLs, routes)";
              icon = "headscale.png";
            };
          }
        ];
      }
      {
        "Apps (asgard)" = [
          {
            "Firefly III" = {
              href = "https://firefly.lan.valgrindr.net";
              description = "Personal finance";
              icon = "firefly.png";
            };
          }
          {
            "Ghostfolio" = {
              href = "https://ghostfolio.lan.valgrindr.net";
              description = "Investment tracker";
              icon = "ghostfolio.png";
            };
          }
          {
            "Home Assistant" = {
              href = "https://home.lan.valgrindr.net";
              description = "Home automation";
              icon = "home-assistant.png";
            };
          }
        ];
      }
    ];

    widgets = [
      {
        resources = {
          label = "bifrost";
          cpu = true;
          memory = true;
          disk = "/";
        };
      }
      {
        datetime = {
          text_size = "xl";
          format = {
            timeStyle = "short";
            dateStyle = "long";
            hourCycle = "h23";
          };
        };
      }
      {
        search = {
          provider = "duckduckgo";
          target = "_blank";
        };
      }
    ];

    bookmarks = [
      {
        "Repos" = [
          {
            "nix-config" = [
              {
                abbr = "NX";
                href = "https://github.com/sanfeps/nix-config";
              }
            ];
          }
        ];
      }
    ];
  };

  services.caddy.virtualHosts."*.lan.valgrindr.net".extraConfig = ''
    @homepage host ${virtualHost}
    handle @homepage {
      reverse_proxy 127.0.0.1:${toString listenPort}
    }
  '';
}
