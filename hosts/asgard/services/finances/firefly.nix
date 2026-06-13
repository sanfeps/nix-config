{
  config,
  pkgs,
  ...
}: let
  virtualHost = "firefly.lan.valgrindr.net";
in {
  sops.secrets."finances/firefly-app-key" = {
    owner = "firefly-iii";
    mode = "0400";
  };

  services.postgresql = {
    ensureDatabases = ["firefly-iii"];
    ensureUsers = [
      {
        name = "firefly-iii";
        ensureDBOwnership = true;
      }
    ];
  };

  services.firefly-iii = {
    enable = true;
    enableNginx = false;
    # Run firefly-iii under the caddy group so the PHP-FPM socket
    # is reachable by the Caddy reverse proxy.
    group = "caddy";
    inherit virtualHost;
    # npm patch: nixpkgs pins nodejs-slim (no npm) in nativeBuildInputs while
    # the build runs npmConfigHook → "npm: command not found". Swap in full nodejs.
    package = pkgs.firefly-iii.overrideAttrs (old: {
      nativeBuildInputs = (old.nativeBuildInputs or []) ++ [pkgs.nodejs];
    });
    settings = {
      APP_ENV = "production";
      APP_URL = "https://${virtualHost}";
      SITE_OWNER = "sanfelixguajardo@gmail.com";
      DB_CONNECTION = "pgsql";
      DB_DATABASE = "firefly-iii";
      DB_USERNAME = "firefly-iii";
      APP_KEY_FILE = config.sops.secrets."finances/firefly-app-key".path;
    };
  };

  # Same tmpfiles race as the importer; harmless to declare even though
  # firefly-iii happened to win the race on first boot.
  systemd.services.firefly-iii-setup.after = ["systemd-tmpfiles-setup.service"];

  # asgard's own Caddy terminates TLS for this vhost (per-host-caddy Phase 3),
  # so PHP sees a genuine https:// request and Symfony's Request::isSecure()
  # returns true on its own — no more lying with `env HTTPS on` /
  # `env SERVER_PORT 443`, no trust-proxy plumbing. Caddy talks straight to
  # PHP-FPM's Unix socket; nothing crosses hosts.
  services.caddy.virtualHosts."${virtualHost}".extraConfig = ''
    root * ${config.services.firefly-iii.package}/public
    php_fastcgi unix/${config.services.phpfpm.pools.firefly-iii.socket}
    file_server
  '';

  environment.persistence."${config.hostSpec.persistFolder}".directories = [
    {
      directory = "/var/lib/firefly-iii";
      user = "firefly-iii";
      group = "caddy";
      mode = "0710";
    }
  ];
}
