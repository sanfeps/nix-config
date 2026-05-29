{
  config,
  lib,
  pkgs,
  ...
}: let
  tailscale = lib.getExe pkgs.tailscale;
  jq = lib.getExe pkgs.jq;
  tr = "${pkgs.coreutils}/bin/tr";
  loginServer = "https://headscale.valgrindr.net";
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

  sops.secrets."tailscale-preauth-key" = {
    sopsFile = ../common/secrets.yaml;
    mode = "0400";
  };

  systemd.services.tailscale-autoconnect-valgrindr = {
    description = "Auto-enroll host into Headscale using sops-managed preauth key";
    after = [
      "tailscaled.service"
      "network-online.target"
      "sops-nix.service"
    ];
    wants = [
      "tailscaled.service"
      "network-online.target"
    ];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "oneshot";
      TimeoutStartSec = "30s";
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
        --authkey "$(${tr} -d '\n' < ${lib.escapeShellArg config.sops.secrets."tailscale-preauth-key".path})"
    '';
  };

  environment.systemPackages = [
    (pkgs.writeShellScriptBin "tailscale-login-valgrindr" ''
      exec ${tailscale} up \
        --login-server ${lib.escapeShellArg loginServer} \
        --accept-dns=true \
        "$@"
    '')
  ];
}
