{
  config,
  lib,
  ...
}: let
  # bifrost owns LAN DNS. Each rewrite points a *.lan.valgrindr.net name at the
  # host that terminates TLS for it: bifrost-local services → bifrostIp, asgard
  # apps (immich, ghostfolio, home, firefly) → asgardIp (their own Caddy).
  bifrostIp = "192.168.1.55";
  asgardIp = "192.168.1.54";
  lanZone = "lan.valgrindr.net";
  webPort = 3000;
  # bcrypt hash for the AdGuard webUI admin (same recipe as asgard).
  # Rotate with:
  #   nix shell nixpkgs#apacheHttpd -c htpasswd -nbB sanfe '<pass>' | cut -d: -f2
  adminBcrypt = "$2y$05$UJFA2qOb1d.tzQmJSeCFXurCL1aVqQ1Gdn.imHh5HrGQcc.8p.AUi";
in {
  # systemd-resolved owns 127.0.0.53:53 by default; turn its stub listener off
  # so AdGuard can bind :53 on every interface.
  services.resolved.settings.Resolve.DNSStubListener = "no";

  # adguardhome's openFirewall only opens the webUI port; DNS needs explicit holes.
  networking.firewall.allowedTCPPorts = [53];
  networking.firewall.allowedUDPPorts = [53];

  services.adguardhome = {
    enable = true;
    mutableSettings = false;
    openFirewall = true;
    host = "127.0.0.1";
    port = webPort;
    settings = {
      users = [
        {
          name = "sanfe";
          password = adminBcrypt;
        }
      ];
      dns = {
        bind_hosts = ["0.0.0.0"];
        port = 53;
        upstream_dns = ["https://dns.quad9.net/dns-query"];
        bootstrap_dns = [
          "9.9.9.9"
          "149.112.112.112"
        ];
        cache_size = 4194304;
      };
      filtering = {
        protection_enabled = true;
        rewrites_enabled = true;
        rewrites = [
          {
            domain = "adguard.${lanZone}";
            answer = bifrostIp;
            enabled = true;
          }
          {
            # per-host-caddy Phase 2a: ghostfolio is fronted by asgard's own Caddy.
            domain = "ghostfolio.${lanZone}";
            answer = asgardIp;
            enabled = true;
          }
          {
            # per-host-caddy Phase 2b: home-assistant is fronted by asgard's own Caddy.
            domain = "home.${lanZone}";
            answer = asgardIp;
            enabled = true;
          }
          {
            # mqtt is plain TCP (mosquitto), not HTTP. Caddy doesn't proxy it.
            # Rewrite kept for clients that point their MQTT URL at this name.
            # TODO(phase 3b): rebind mosquitto to LAN or remove this rewrite.
            domain = "mqtt.${lanZone}";
            answer = bifrostIp;
            enabled = true;
          }
          {
            # per-host-caddy Phase 3: firefly is fronted by asgard's own Caddy,
            # which terminates TLS and talks straight to PHP-FPM's Unix socket.
            domain = "firefly.${lanZone}";
            answer = asgardIp;
            enabled = true;
          }
          {
            domain = "homepage.${lanZone}";
            answer = bifrostIp;
            enabled = true;
          }
          {
            domain = "headplane.${lanZone}";
            answer = bifrostIp;
            enabled = true;
          }
          # per-host-caddy Phase 4: the media stack is fronted by asgard's own
          # Caddy (vhosts in hosts/asgard/services/media/caddy.nix).
          {
            domain = "jellyfin.${lanZone}";
            answer = asgardIp;
            enabled = true;
          }
          {
            domain = "seerr.${lanZone}";
            answer = asgardIp;
            enabled = true;
          }
          {
            domain = "qbittorrent.${lanZone}";
            answer = asgardIp;
            enabled = true;
          }
          {
            domain = "prowlarr.${lanZone}";
            answer = asgardIp;
            enabled = true;
          }
          {
            domain = "sonarr.${lanZone}";
            answer = asgardIp;
            enabled = true;
          }
          {
            domain = "radarr.${lanZone}";
            answer = asgardIp;
            enabled = true;
          }
          {
            # per-host-caddy Phase 1: immich is fronted by asgard's own Caddy.
            domain = "immich.${lanZone}";
            answer = asgardIp;
            enabled = true;
          }
        ];
      };
    };
  };

  # bifrost itself resolves through its own AdGuard so rewrites apply locally.
  # Quad9 fallback keeps DNS working if AdGuard is down mid-rebuild.
  networking.nameservers = lib.mkForce [
    "127.0.0.1"
    "9.9.9.9"
  ];
}
