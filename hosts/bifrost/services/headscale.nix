{
  config,
  pkgs,
  ...
}: let
  loginDomain = "headscale.valgrindr.net";
  tailnetDomain = "ts.yggdrasil.lo";
  derpPort = 3478;
  bootstrapUser = "yggdrasil";
  # Tailscale-compatible policy v2 (HuJSON). Lets asgard (still on the tailnet
  # as a regular peer post-cutover) advertise exit-node routes without anyone
  # running `headscale nodes approve-routes` by hand. Add more entries to
  # autoApprovers.routes if subnet routers join later.
  policyFile = pkgs.writeText "headscale-policy.hujson" ''
    {
      "groups": {
        "group:exit-approvers": ["${bootstrapUser}@"]
      },
      "acls": [
        {"action": "accept", "src": ["*"], "dst": ["*:*"]}
      ],
      "autoApprovers": {
        "exitNode": ["group:exit-approvers"],
        "routes": {}
      }
    }
  '';
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
        # Bifrost owns LAN DNS post-cutover; push its tailnet IP so members keep
        # working DNS off-LAN (a laptop on foreign wifi can't reach 192.168.1.55).
        nameservers.global = ["100.64.0.3"];
      };
      prefixes = {
        v4 = "100.64.0.0/10";
        v6 = "fd7a:115c:a1e0::/48";
      };
      logtail.enabled = false;
      log.level = "warn";
      derp = {
        urls = ["https://controlplane.tailscale.com/derpmap/default"];
        auto_update_enabled = true;
        server = {
          enable = true;
          region_id = 999;
          region_code = "val";
          region_name = "valgrindr";
          stun_listen_addr = "0.0.0.0:${toString derpPort}";
        };
      };
      policy = {
        mode = "file";
        path = "${policyFile}";
      };
    };
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
  ];

  networking.firewall.allowedUDPPorts = [derpPort];

  sops.secrets."headscale-bootstrap-prefix".mode = "0400";
  sops.secrets."headscale-bootstrap-hash".mode = "0400";

  # Idempotent (INSERT OR IGNORE) — safe to keep enabled after migrating the
  # SQLite DB from asgard. On a fresh DB it seeds the bootstrap user + preauth
  # key; on a migrated DB it's a no-op.
  systemd.services.headscale-bootstrap = {
    description = "Seed headscale DB with declarative user and preauth key";
    after = ["headscale.service"];
    wants = ["headscale.service"];
    wantedBy = ["multi-user.target"];
    path = [
      pkgs.coreutils
      pkgs.sqlite
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      TimeoutStartSec = "60s";
    };
    script = ''
      set -euo pipefail

      DB=/var/lib/headscale/db.sqlite

      for _ in $(seq 1 60); do
        if [ -f "$DB" ] && sqlite3 "$DB" "SELECT 1 FROM users LIMIT 1;" >/dev/null 2>&1; then
          break
        fi
        sleep 1
      done
      sqlite3 "$DB" "SELECT 1 FROM users LIMIT 1;" >/dev/null

      sqlite3 "$DB" "INSERT OR IGNORE INTO users (name, created_at, updated_at) VALUES ('${bootstrapUser}', datetime('now'), datetime('now'));"

      USER_ID=$(sqlite3 "$DB" "SELECT id FROM users WHERE name = '${bootstrapUser}' AND deleted_at IS NULL LIMIT 1;")
      [ -n "$USER_ID" ] || { echo "${bootstrapUser} user not found after insert" >&2; exit 1; }

      PREFIX=$(cat ${config.sops.secrets."headscale-bootstrap-prefix".path})
      HASH=$(cat ${config.sops.secrets."headscale-bootstrap-hash".path})

      SQL=$(printf "INSERT INTO pre_auth_keys (user_id, prefix, hash, reusable, ephemeral, used, created_at) SELECT %s, '%s', '%s', 1, 0, 0, datetime('now') WHERE NOT EXISTS (SELECT 1 FROM pre_auth_keys WHERE prefix = '%s');" "$USER_ID" "$PREFIX" "$HASH" "$PREFIX")
      sqlite3 "$DB" "$SQL"
    '';
  };
}
