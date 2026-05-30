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
    #
    # HTTPS note: trusted-proxy handling in Firefly is unreliable (we patched
    # bootstrap/app.php to call $middleware->trustProxies(at: '*') and verified
    # the line was active in the store path, but the runtime still emitted
    # http:// URLs in 302 Locations and asset() helpers). Instead of fighting
    # Laravel internals, we lie to PHP at the FastCGI layer: HTTPS=on +
    # SERVER_PORT=443 are passed as CGI params from asgard's Caddy (see the
    # php_fastcgi block below). With $_SERVER['HTTPS']='on', Symfony's
    # Request::isSecure() returns true and the URL generator emits https://
    # everywhere, no trust-proxy plumbing required.
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

  # FastCGI params HTTPS=on / SERVER_PORT=443 are how we tell Firefly's PHP
  # that the original (bifrost-side) connection is https, without depending on
  # trustProxies (which we couldn't get to fire — see HTTPS note above). With
  # $_SERVER['HTTPS']='on' set, Symfony Request::isSecure() returns true and
  # Laravel's URL generator emits https:// for asset(), route(), redirect()
  # alike — fixing both the 302 Location and the mixed-content asset URLs.
  services.caddy.virtualHosts."http://${virtualHost}".extraConfig = ''
    root * ${config.services.firefly-iii.package}/public
    php_fastcgi unix/${config.services.phpfpm.pools.firefly-iii.socket} {
      env HTTPS on
      env SERVER_PORT 443
    }
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
