{config, ...}: let
  listenPort = 2586;
  virtualHost = "ntfy.lan.valgrindr.net";
in {
  # ntfy — self-hosted push-notification bus for the whole cluster. Anything
  # that can run curl publishes to a topic; the Android app holds a direct
  # connection to this server (no FCM/ntfy.sh relay). First publisher: ZED on
  # draupnir (topic zfs-draupnir, see hosts/draupnir/default.nix).
  #
  # Auth is deny-all; users/tokens are provisioned declaratively via env vars
  # (NTFY_AUTH_USERS/TOKENS/ACCESS) from a sops env file, which is exactly what
  # the module's environmentFile option is for — nothing secret in the store.
  # Phone login password: sops -d --extract '["ntfy"]["password-sanfe"]'
  # hosts/bifrost/secrets.yaml.
  sops.secrets."ntfy/auth-env" = {};

  services.ntfy-sh = {
    enable = true;
    environmentFile = config.sops.secrets."ntfy/auth-env".path;
    settings = {
      base-url = "https://${virtualHost}";
      listen-http = "127.0.0.1:${toString listenPort}";
      behind-proxy = true;
      auth-default-access = "deny-all";
      # DynamicUser + StateDirectory → really /var/lib/private/ntfy-sh; persists
      # by virtue of bifrost's non-wiped rootfs (same as AdGuard — no
      # environment.persistence declaration, see root CLAUDE.md).
      auth-file = "/var/lib/ntfy-sh/user.db";
      cache-file = "/var/lib/ntfy-sh/cache.db";
    };
  };

  services.caddy.virtualHosts."*.lan.valgrindr.net".extraConfig = ''
    @ntfy host ${virtualHost}
    handle @ntfy {
      reverse_proxy 127.0.0.1:${toString listenPort}
    }
  '';
}
