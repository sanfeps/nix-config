{
  config,
  pkgs,
  ...
}: let
  port = 3001;
  virtualHost = "headplane.lan.valgrindr.net";
in {
  # COOKIE_SECRET signs Headplane's session cookies. Headplane 0.6.3 wants
  # exactly 32 characters, but the existing secret in sops is a 64-char hex
  # string. Keep the stronger-at-rest value and trim it when rendering the
  # runtime config below so we do not need to rotate the secret just for this.
  sops.secrets."headplane-cookie-secret".mode = "0400";

  # Headplane 0.6+ is YAML-configured (env vars are ignored for server /
  # headscale settings). Render the file at runtime after sops has materialised
  # the secret, because the current secret is longer than Headplane accepts and
  # needs to be trimmed before it lands in the YAML.
  #
  # `cookie_secure: false` — TLS is terminated at Caddy; between Caddy and
  # Headplane the request is plain HTTP on loopback. With `true`, Headplane
  # would refuse to issue the session cookie since `req.secure` is false.
  #
  # `integration` block deliberately omitted: Headplane runs in view-only mode
  # for headscale reloads. After ACL edits via the UI, `systemctl reload
  # headscale` manually on bifrost.
  systemd.services.headplane-config = {
    description = "Render Headplane runtime config";
    wantedBy = ["multi-user.target"];
    before = ["podman-headplane.service"];
    after = ["sops-install-secrets.service"];
    wants = ["sops-install-secrets.service"];
    path = [pkgs.coreutils];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      RuntimeDirectory = "headplane";
      RuntimeDirectoryMode = "0700";
    };
    script = ''
      set -euo pipefail

      cookie_secret="$(tr -d '\n' < ${config.sops.secrets."headplane-cookie-secret".path} | cut -c1-32)"
      [ "''${#cookie_secret}" -eq 32 ] || {
        echo "headplane-cookie-secret must contain at least 32 characters" >&2
        exit 1
      }

      umask 077
      cat > /run/headplane/config.yaml <<EOF
      server:
        host: "127.0.0.1"
        port: ${toString port}
        cookie_secret: "$cookie_secret"
        cookie_secure: false

      headscale:
        url: "http://127.0.0.1:8080"
        public_url: "https://headscale.valgrindr.net"
        config_path: "/etc/headscale/config.yaml"
        config_strict: false
      EOF
    '';
  };

  systemd.services.podman-headplane = {
    after = ["headplane-config.service"];
    requires = ["headplane-config.service"];
  };

  services.containers.headplane = {
    enable = true;
    inherit port;
    configFile = "/run/headplane/config.yaml";
  };

  services.caddy.virtualHosts."*.lan.valgrindr.net".extraConfig = ''
    @headplaneRoot {
      host ${virtualHost}
      path /
    }
    redir @headplaneRoot /admin 308

    @headplane host ${virtualHost}
    handle @headplane {
      reverse_proxy 127.0.0.1:${toString port}
    }
  '';

  environment.persistence."/persist".directories = [
    {
      directory = "/var/lib/headplane";
      user = "root";
      group = "root";
      mode = "0700";
    }
  ];
}
