{
  config,
  lib,
  ...
}: let
  lanIp = "192.168.1.54";
  lanZone = "lan.valgrindr.net";
  webPort = 3000;
  # bcrypt hash of "changeme"; swap via `htpasswd -nbB admin <pass> | cut -d: -f2`.
  # TODO: move to sops template once C is in place.
  adminBcrypt = "$2y$05$QnLhYrJn0VcVBFD3YuHRreH3cxVn3yxhBnPn8cjy1ZKQe9yLLJ64e";
in {
  # systemd-resolved owns 127.0.0.53:53 by default; turn its stub listener off
  # so AdGuard can bind :53 on every interface.
  services.resolved.settings.Resolve.DNSStubListener = "no";

  services.adguardhome = {
    enable = true;
    mutableSettings = false;
    openFirewall = true;
    host = "127.0.0.1";
    port = webPort;
    settings = {
      users = [
        {
          name = "admin";
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
        rewrites = [
          {
            domain = "firefly.${lanZone}";
            answer = lanIp;
          }
          {
            domain = "home.${lanZone}";
            answer = lanIp;
          }
          {
            domain = "mqtt.${lanZone}";
            answer = lanIp;
          }
          {
            domain = "adguard.${lanZone}";
            answer = lanIp;
          }
        ];
      };
      filtering.protection_enabled = true;
    };
  };

  # asgard itself resolves through AdGuard so rewrites apply locally too.
  networking.nameservers = lib.mkForce ["127.0.0.1"];

  services.caddy.virtualHosts."http://adguard.${lanZone}".extraConfig = ''
    reverse_proxy 127.0.0.1:${toString webPort}
  '';
}
