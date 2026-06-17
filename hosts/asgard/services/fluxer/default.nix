# Fluxer — self-hosted Discord alternative (https://fluxer.app, repo fluxerapp/fluxer).
#
# Fluxer has no native nixpkgs package/module and ships only as a ~22-container
# Docker Compose stack (docs.fluxer.app/operator). It's too large and fast-moving
# to hand-port to oci-containers, so we VENDOR the upstream compose files verbatim
# (docker-compose.yml, Caddyfile, livekit.yaml — see this dir) and run them via
# podman-compose under a declarative systemd unit. This is a deliberate exception
# to the repo's "no docker-compose inside Nix" rule (see services/media/CLAUDE.md):
# that rule held because native NixOS services existed for the media stack — here
# there is no native path.
#
# Ingress: asgard's own Caddy (services.caddyNjalla) already owns :80/:443, so
# Fluxer's bundled Caddy is loopback-only HTTP (FLUXER_CADDY_SITE_ADDRESS=:80,
# published at 127.0.0.1:8080 — see the LOCAL PATCH in docker-compose.yml) and
# asgard's Caddy fronts it at https://fluxer.lan.valgrindr.net. LAN + tailnet only.
#
# Secrets live in sops (hosts/asgard/secrets.yaml under fluxer/) and are rendered
# into the runtime .env via sops.templates — the repo stays secrets-free. The
# import in services/default.nix stays COMMENTED until the secrets are seeded; see
# CLAUDE.md in this directory for the one-time bootstrap.
{
  config,
  pkgs,
  ...
}: let
  domain = "fluxer.lan.valgrindr.net";
  stateDir = "/var/lib/fluxer";

  composeFile = ./docker-compose.yml;
  caddyfile = ./Caddyfile;
  livekitConf = ./livekit.yaml;

  ph = name: config.sops.placeholder."fluxer/${name}";

  podmanCompose = "${pkgs.podman-compose}/bin/podman-compose";
  composeArgs = "--env-file ${stateDir}/.env -f ${stateDir}/docker-compose.yml";

  # Stage the vendored static files + the sops-rendered .env into the runtime
  # working dir. Relative volume mounts (./Caddyfile, ./livekit.yaml) and compose
  # ${VAR} substitution resolve from here.
  stage = pkgs.writeShellScript "fluxer-stage" ''
    set -eu
    install -d -m 0700 ${stateDir}
    install -m 0444 ${composeFile} ${stateDir}/docker-compose.yml
    install -m 0444 ${caddyfile}   ${stateDir}/Caddyfile
    install -m 0444 ${livekitConf} ${stateDir}/livekit.yaml
    install -m 0600 ${config.sops.templates."fluxer.env".path} ${stateDir}/.env
  '';
in {
  # --- Secrets (seed these in `sops hosts/asgard/secrets.yaml` before enabling) ---
  sops.secrets = builtins.listToAttrs (map (n: {
      name = "fluxer/${n}";
      value = {mode = "0400";};
    }) [
      "postgres-password"
      "meili-master-key"
      "s3-secret-key"
      "sudo-mode-secret"
      "connection-initiation-secret"
      "gateway-rpc-auth-token"
      "media-proxy-secret-key"
      "media-proxy-upload-relay-secret-base64"
      "admin-secret-key-base"
      "admin-oauth-client-secret"
      "livekit-api-secret"
      "vapid-public-key"
      "vapid-private-key"
    ]);

  # Full .env rendered at activation: literal non-secrets + sops placeholders.
  sops.templates."fluxer.env" = {
    mode = "0400";
    restartUnits = ["fluxer.service"];
    content = ''
      FLUXER_DOMAIN=${domain}
      FLUXER_PUBLIC_SCHEME=https
      FLUXER_PUBLIC_PORT=443
      FLUXER_CADDY_SITE_ADDRESS=:80

      FLUXER_REGISTRY_OWNER=fluxerapp
      FLUXER_REGISTRY=ghcr.io/fluxerapp
      FLUXER_IMAGE_TAG=v1

      POSTGRES_PASSWORD=${ph "postgres-password"}
      MEILI_MASTER_KEY=${ph "meili-master-key"}
      FLUXER_S3_ACCESS_KEY=fluxer
      FLUXER_S3_SECRET_KEY=${ph "s3-secret-key"}

      FLUXER_SUDO_MODE_SECRET=${ph "sudo-mode-secret"}
      FLUXER_CONNECTION_INITIATION_SECRET=${ph "connection-initiation-secret"}
      FLUXER_GATEWAY_RPC_AUTH_TOKEN=${ph "gateway-rpc-auth-token"}
      FLUXER_MEDIA_PROXY_SECRET_KEY=${ph "media-proxy-secret-key"}
      FLUXER_MEDIA_PROXY_UPLOAD_RELAY_SECRET_BASE64=${ph "media-proxy-upload-relay-secret-base64"}
      FLUXER_ADMIN_SECRET_KEY_BASE=${ph "admin-secret-key-base"}
      FLUXER_ADMIN_OAUTH_CLIENT_SECRET=${ph "admin-oauth-client-secret"}

      FLUXER_VAPID_PUBLIC_KEY=${ph "vapid-public-key"}
      FLUXER_VAPID_PRIVATE_KEY=${ph "vapid-private-key"}
      FLUXER_VAPID_EMAIL=admin@${domain}

      LIVEKIT_API_KEY=fluxer
      LIVEKIT_API_SECRET=${ph "livekit-api-secret"}

      FLUXER_EMAIL_ENABLED=false
      FLUXER_DISCOVERY_ENABLED=true
    '';
  };

  # --- The stack ---
  systemd.services.fluxer = {
    description = "Fluxer self-hosted chat stack (podman-compose)";
    wantedBy = ["multi-user.target"];
    after = ["network-online.target" "podman.service"];
    wants = ["network-online.target"];
    # podman-compose shells out to `podman`; coreutils for the staging `install`.
    path = [pkgs.podman pkgs.podman-compose pkgs.coreutils];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      # First boot pulls ~15 images and the api healthcheck has a 90s start_period.
      TimeoutStartSec = "1800";
      # Create /var/lib/fluxer before systemd chdirs into WorkingDirectory and
      # before ExecStartPre stages files into it.
      StateDirectory = "fluxer";
      StateDirectoryMode = "0700";
      WorkingDirectory = stateDir;
      ExecStartPre = "${stage}";
      ExecStart = "${podmanCompose} ${composeArgs} up -d";
      ExecStop = "${podmanCompose} ${composeArgs} down";
    };
  };

  # asgard's own Caddy fronts the loopback-bound bundled Caddy. The bundled Caddy
  # does all internal path routing (/api, /gateway WS, /media, /livekit, /admin,
  # static, catch-all → app-proxy), so a single reverse_proxy is enough.
  services.caddy.virtualHosts."${domain}".extraConfig = ''
    reverse_proxy 127.0.0.1:8080
  '';

  # LiveKit WebRTC media (LAN/tailnet voice). Web traffic rides asgard's existing
  # :443, so no extra web hole. Tailnet voice may need a TURN/external-IP override
  # if STUN can't see a reachable address — revisit if calls fail over tailscale.
  networking.firewall.allowedTCPPorts = [7881];
  networking.firewall.allowedUDPPorts = [7882];
}
