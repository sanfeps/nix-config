{
  config,
  pkgs,
  ...
}: let
  record = "headscale.valgrindr.net";
in {
  sops.secrets."njalla-key-headscale" = {
    sopsFile = ../secrets.yaml;
    mode = "0400";
  };

  systemd.services.njalla-ddns = {
    description = "Update Njalla DNS record ${record}";
    after = ["network-online.target"];
    wants = ["network-online.target"];
    path = [pkgs.curl];
    serviceConfig.Type = "oneshot";
    script = ''
      KEY=$(cat ${config.sops.secrets."njalla-key-headscale".path})
      curl --silent --show-error --fail --max-time 30 --get \
        --data-urlencode "h=${record}" \
        --data-urlencode "k=$KEY" \
        --data "auto" \
        https://njal.la/update/
      echo
    '';
  };

  systemd.timers.njalla-ddns = {
    description = "Periodically refresh Njalla DNS record ${record}";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnBootSec = "1min";
      OnUnitActiveSec = "10min";
      Unit = "njalla-ddns.service";
      Persistent = true;
    };
  };
}
