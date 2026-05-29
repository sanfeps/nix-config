{
  config,
  lib,
  ...
}: let
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
      # Rewrites land here in Phase 3 when the cutover from asgard happens.
      filtering = {
        protection_enabled = true;
        rewrites_enabled = true;
        rewrites = [];
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
