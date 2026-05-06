{
  lib,
  pkgs,
  ...
}: let
  tailscale = lib.getExe pkgs.tailscale;
  jq = lib.getExe pkgs.jq;
  tr = "${pkgs.coreutils}/bin/tr";
  loginServer = "https://headscale.valgrindr.net";
  secretDir = "/persist/secrets";
  authKeyPath = "${secretDir}/tailscale-auth-key";
in {
  services.resolved.enable = true;

  services.tailscale = {
    enable = true;
    openFirewall = true;
    useRoutingFeatures = lib.mkDefault "client";
  };

  environment.persistence."/persist".directories = [
    "/var/lib/tailscale"
  ];

  systemd.tmpfiles.rules = [
    "d ${secretDir} 0700 root root -"
  ];

  systemd.services.tailscale-autoconnect-valgrindr = {
    description = "Auto-enroll host into Headscale if an auth key is present";
    after = [
      "tailscaled.service"
      "network-online.target"
    ];
    wants = [
      "tailscaled.service"
      "network-online.target"
    ];
    wantedBy = ["multi-user.target"];
    unitConfig.ConditionPathExists = authKeyPath;
    serviceConfig = {
      Type = "oneshot";
    };
    path = [
      pkgs.coreutils
      pkgs.tailscale
      pkgs.jq
    ];
    script = ''
      state="$(${tailscale} status --json 2>/dev/null | ${jq} -r '.BackendState // empty' || true)"

      case "$state" in
        Running|Starting)
          exit 0
          ;;
      esac

      exec ${tailscale} up \
        --login-server ${lib.escapeShellArg loginServer} \
        --accept-dns=true \
        --authkey "$(${tr} -d '\n' < ${lib.escapeShellArg authKeyPath})"
    '';
  };

  environment.systemPackages = [
    (pkgs.writeShellScriptBin "tailscale-login-valgrindr" ''
      exec ${tailscale} up \
        --login-server ${lib.escapeShellArg loginServer} \
        --accept-dns=true \
        "$@"
    '')
    (pkgs.writeShellScriptBin "tailscale-auth-key-install-valgrindr" ''
      set -euo pipefail

      install -d -m 700 ${lib.escapeShellArg secretDir}
      install -m 600 /dev/stdin ${lib.escapeShellArg authKeyPath}
      systemctl restart tailscale-autoconnect-valgrindr.service
      systemctl --no-pager --full status tailscale-autoconnect-valgrindr.service
    '')
  ];
}
