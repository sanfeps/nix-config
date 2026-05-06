{
  config,
  ...
}: let
  loginDomain = "headscale.valgrindr.net";
  tailnetDomain = "yggdrasil.local";
  derpPort = 3478;
in {
  services.headscale = {
    enable = true;
    address = "127.0.0.1";
    port = 8080;
    settings = {
      server_url = "https://${loginDomain}";
      dns = {
        override_local_dns = true;
        base_domain = tailnetDomain;
        magic_dns = true;
        nameservers.global = [
          "1.1.1.1"
          "1.0.0.1"
        ];
      };
      prefixes = {
        v4 = "100.64.0.0/10";
        v6 = "fd7a:115c:a1e0::/48";
      };
      logtail.enabled = false;
      log.level = "warn";
      derp = {
        urls = [];
        auto_update_enabled = false;
        server = {
          enable = true;
          region_id = 999;
          region_code = "val";
          region_name = "valgrindr";
          stun_listen_addr = "0.0.0.0:${toString derpPort}";
        };
      };
    };
  };

  services.caddy = {
    enable = true;
    virtualHosts."${loginDomain}".extraConfig = ''
      reverse_proxy 127.0.0.1:${toString config.services.headscale.port}
    '';
  };

  users.users.${config.hostSpec.username}.extraGroups = [
    config.services.headscale.group
  ];

  environment.systemPackages = [
    config.services.headscale.package
  ];

  environment.persistence."/persist".directories = [
    {
      directory = "/var/lib/headscale";
      user = config.services.headscale.user;
      group = config.services.headscale.group;
      mode = "0750";
    }
    {
      directory = "/var/lib/caddy";
      user = "caddy";
      group = "caddy";
      mode = "0700";
    }
  ];

  networking.firewall = {
    allowedTCPPorts = [
      80
      443
    ];
    allowedUDPPorts = [derpPort];
  };
}
