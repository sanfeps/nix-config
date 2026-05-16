{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.njalla-ddns;
  secretsDir = "/persist/secrets/ddns-njalla";
in {
  options.services.njalla-ddns = {
    enable = lib.mkEnableOption "Njalla dynamic DNS updater";

    records = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = ''
        Fully-qualified DNS records to keep pointed at this host's public IP.
        For each record "foo.example.com" the per-record Njalla DDNS key must
        be placed at ${secretsDir}/foo.example.com (root:root, mode 0600,
        plain text — surrounding whitespace is stripped).
      '';
      example = ["headscale.valgrindr.net"];
    };

    interval = lib.mkOption {
      type = lib.types.str;
      default = "5min";
      description = "How often to refresh the records (systemd OnUnitActiveSec value).";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.njalla-ddns = {
      description = "Update Njalla DNS records with current public IP";
      after = ["network-online.target"];
      wants = ["network-online.target"];

      path = [pkgs.curl pkgs.coreutils];

      serviceConfig = {
        Type = "oneshot";
      };

      script =
        lib.concatMapStringsSep "\n" (record: ''
          if [ -r ${secretsDir}/${record} ]; then
            KEY=$(tr -d '[:space:]' < ${secretsDir}/${record})
            echo "Updating ${record}"
            curl --silent --show-error --fail --max-time 30 --get \
              --data-urlencode "h=${record}" \
              --data-urlencode "k=$KEY" \
              "https://njal.la/update/"
            echo
          else
            echo "Skipping ${record}: no key at ${secretsDir}/${record}" >&2
          fi
        '')
        cfg.records;
    };

    systemd.timers.njalla-ddns = {
      description = "Periodically refresh Njalla DNS records";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "1min";
        OnUnitActiveSec = cfg.interval;
        Unit = "njalla-ddns.service";
        Persistent = true;
      };
    };
  };
}
