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
  cfg = config.services.tailscaleClient;
  acceptRoutesFlag = lib.boolToString cfg.acceptRoutes;
in {
  options.services.tailscaleClient.acceptRoutes = lib.mkOption {
    type = lib.types.bool;
    default = false;
    example = true;
    description = ''
      Whether this host accepts subnet routes advertised on the tailnet
      (`tailscale up/set --accept-routes`).

      Leave this false on any host physically resident on an advertised subnet
      (e.g. the 192.168.1.0/24 LAN): accepting the route installs that subnet into
      tailscale's routing table ahead of the main table, so the host tunnels traffic
      to its own LAN through the subnet router. Replies to inbound LAN connections
      then leave with a source the tunnel won't carry and get blackholed — the host
      becomes unreachable on its LAN IP while staying reachable on its tailnet IP.

      Only enable on genuinely off-LAN / roaming clients that need to reach LAN
      ranges via the subnet router; those reach LAN hosts through the router's SNAT,
      so they work in both locations without this trap.
    '';
  };

  config = {
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
          --accept-routes=${acceptRoutesFlag} \
          --authkey "$(${tr} -d '\n' < ${lib.escapeShellArg config.sops.secrets."tailscale-preauth-key".path})"
      '';
    };

    # The autoconnect oneshot only runs `tailscale up` on first enroll, so an
    # already-enrolled host keeps whatever --accept-routes value is persisted in
    # tailscaled.state (e.g. a stale `true` from a manual `tailscale-login-valgrindr`
    # run). Enforce the declarative value on every boot/deploy. `tailscale set
    # --accept-routes` is independent of the advertise/exit-node prefs, so it does
    # not clobber the subnet-router config on bifrost.
    systemd.services.tailscale-accept-routes-valgrindr = {
      description = "Enforce declarative --accept-routes on the tailnet daemon";
      after = [
        "tailscaled.service"
        "tailscale-autoconnect-valgrindr.service"
      ];
      requires = ["tailscaled.service"];
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${tailscale} set --accept-routes=${acceptRoutesFlag}";
      };
    };

    environment.systemPackages = [
      (pkgs.writeShellScriptBin "tailscale-login-valgrindr" ''
        exec ${tailscale} up \
          --login-server ${lib.escapeShellArg loginServer} \
          --accept-dns=true \
          --accept-routes=${acceptRoutesFlag} \
          "$@"
      '')
    ];
  };
}
