{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
# Mullvad WireGuard network namespace for the media acquisition plane.
#
# Egress chokepoint for qbittorrent + prowlarr + sonarr + radarr. Each
# confined service opts in with:
#
#   systemd.services.<name>.vpnConfinement = {
#     enable = true;
#     vpnNamespace = "mullvad";
#   };
#
# and exposes its WebUI back to the host via:
#
#   vpnNamespaces.mullvad.portMappings = [
#     { from = <hostPort>; to = <nsPort>; protocol = "tcp"; }
#   ];
#
# asgard's own Caddy then reverse-proxies https://<svc>.lan.valgrindr.net to
# the namespace veth IP 192.168.15.1:<nsPort> (see media/caddy.nix); the
# portMapping above is what installs the in-namespace veth INPUT ACCEPT.
#
# ──────────────────────────────────────────────────────────────────────────
# Mullvad wg conf bootstrap (one-time, manual):
#
#   1. Log in at mullvad.net → WireGuard configuration generator.
#      Generate a key, pick a single server, download the `.conf`.
#   2. Edit the conf locally:
#        - Confirm `DNS = 10.64.0.1` is present under [Interface]. If not,
#          add it. This is the leak-prevention belt to VPN-Confinement's
#          NSCD-socket suspenders (which are only tested for UDP DNS).
#        - Keep `Address`, `PrivateKey`, `[Peer]` block as-is.
#   3. `sops hosts/asgard/secrets.yaml` → add a key `media/mullvad-wg-conf`
#      with the full file content as a multiline string (`|` in yaml).
#   4. Deploy asgard. The namespace comes up at activation.
let
  ns = "mullvad"; # ≤7 chars; VPN-Confinement uses this as ifname suffix.

  # nsswitch for the confined services. The host's default puts `resolve`
  # (nss-resolve → systemd-resolved, reachable from the netns over its unix
  # socket) BEFORE `dns`, with `[!UNAVAIL=return]` — so systemd-resolved answers
  # every lookup on the HOST network and the `dns` module (our resolv.conf →
  # 10.64.0.1) is never consulted. That (a) returns AAAA so the *arrs try flaky
  # IPv6 connects over the tunnel (the `SocketException(11)` at *connect* → pool
  # poisoned → Seerr FAILED), and (b) LEAKS DNS out the host instead of the
  # tunnel. Binding this over /etc/nsswitch.conf drops `resolve`/`mymachines` so
  # hosts resolve strictly via `dns` → the netns resolv.conf (10.64.0.1, over the
  # tunnel). `systemd` stays in passwd/group for Prowlarr's DynamicUser.
  # (Regressed with the nixpkgs bump that made systemd-resolved the nss primary.)
  nsswitchConf = pkgs.writeText "${ns}-nsswitch.conf" ''
    passwd:    files systemd
    group:     files [success=merge] systemd
    shadow:    files
    hosts:     files myhostname dns
    networks:  files
    ethers:    files
    services:  files
    protocols: files
    rpc:       files
  '';
in {
  imports = [inputs.vpn-confinement.nixosModules.default];

  sops.secrets."media/mullvad-wg-conf" = {
    mode = "0400";
    # owner unset → root. VPN-Confinement's setup unit reads this at boot.
  };

  vpnNamespaces.${ns} = {
    enable = true;
    wireguardConfigFile = config.sops.secrets."media/mullvad-wg-conf".path;

    # Sources allowed to reach host-side port mappings published by confined
    # services. LAN for direct access, tailnet for remote admin, loopback
    # for any same-host proxy that lands here in the future.
    accessibleFrom = [
      "192.168.1.0/24"
      "100.64.0.0/10"
      "127.0.0.1/32"
    ];

    # portMappings is a list — each service module appends its own entry.
    # Defaults for namespaceAddress (192.168.15.1) are left untouched.
  };

  # Harden DNS resolution inside the namespace. The confined .NET *arrs kept
  # getting `SocketException(11): Resource temporarily unavailable (<host>:443)`
  # at *connect* (not DNS): with systemd-resolved answering (nss `resolve`, see
  # nsswitchConf) they received AAAA and tried IPv6 connects over the tunnel,
  # which flake, poison the SocketsHttpHandler pool, and mark Seerr requests
  # FAILED. Two-part fix: (1) nsswitchConf forces resolution through the netns
  # resolv.conf (10.64.0.1, over the tunnel — no host leak; proven fast+reliable:
  # `dig @10.64.0.1` answers instantly with IPv4); (2) disable IPv6 in the netns
  # below so getaddrinfo (AI_ADDRCONFIG) only ever returns IPv4 → the *arrs never
  # attempt the flaky IPv6 connect. (An in-netns dnsmasq cache was tried and
  # dropped — it wouldn't forward to 10.64.0.1 from inside the netns; the direct
  # resolver is reliable, so caching bought nothing.) mullvad-up does
  # `rm -rf /etc/netns/${ns}` on every (re)start, so we rewrite resolv.conf here.
  systemd.services = lib.mkMerge [
    {
      ${ns}.serviceConfig.ExecStartPost = lib.mkAfter [
        (pkgs.writeShellScript "${ns}-dns-ipv4only" ''
          # Resolve straight to Mullvad's in-tunnel resolver (single-request-reopen
          # sequences the A/AAAA lookups; AAAA is moot with IPv6 disabled below).
          printf 'nameserver 10.64.0.1\noptions single-request-reopen\n' \
            > /etc/netns/${ns}/resolv.conf
          # Kill IPv6 inside the netns so the *arrs only ever get/try IPv4 — the
          # IPv6 tunnel path is what was failing the connects. Runs in the host ns,
          # so hop into the netns to set the (net-namespaced) sysctls.
          ${pkgs.iproute2}/bin/ip netns exec ${ns} \
            ${pkgs.procps}/bin/sysctl -qw net.ipv6.conf.all.disable_ipv6=1 \
                                          net.ipv6.conf.default.disable_ipv6=1 || true
        '')

        # Readiness gate: don't let mullvad.service report "active" until the
        # WireGuard tunnel is actually USABLE (a real DNS answer comes back from
        # Mullvad's in-tunnel resolver 10.64.0.1). VPN-Confinement marks the unit
        # active as soon as the interface is configured, but the handshake needs a
        # few more seconds — so every `After=`/`PartOf=mullvad` dependent used to
        # start against a COLD tunnel and cache the failure: the .NET *arrs poison
        # their SocketsHttpHandler pool (EAI_AGAIN → 503s, Radarr SkyHook, Prowlarr
        # indexer/CF-proxy tests) and Byparr's browser dies with
        # `camoufox InvalidIP: Failed to get IP address`. This is THE race behind
        # "the whole chain breaks after a deploy". Gating here — plus the
        # partOf=mullvad recycle below — fixes it for the entire stack in one spot.
        # `dig @10.64.0.1` runs inside the netns and bypasses nss, so it probes the
        # exact tunnel+resolver path that fails (and the netns firewall permits
        # UDP/53 to that resolver). Bounded to ~30s, then continue anyway: a hard
        # failure here would tear down the whole confined stack via BindsTo, which
        # is worse than a cold start.
        (pkgs.writeShellScript "${ns}-wait-egress" ''
          for i in $(seq 1 30); do
            if [ -n "$(${pkgs.iproute2}/bin/ip netns exec ${ns} \
                  ${pkgs.dnsutils}/bin/dig +short +time=1 +tries=1 @10.64.0.1 api.radarr.video 2>/dev/null)" ]; then
              echo "${ns}: tunnel egress ready after ''${i}s"
              exit 0
            fi
            sleep 1
          done
          echo "${ns}: WARNING tunnel egress not confirmed after 30s; continuing" >&2
          exit 0
        '')
      ];
    }

    # Point every confined service at the netns resolver. VPN-Confinement writes
    # the correct resolver (10.64.0.1) to /etc/netns/${ns}/resolv.conf, but that
    # file is only consumed by `ip netns exec` — a systemd unit joined to the
    # namespace via NetworkNamespacePath keeps the HOST's /etc/resolv.conf, which
    # is the systemd-resolved stub 127.0.0.53. Inside the namespace 127.0.0.53 is
    # a dead address, and glibc's nss-resolve can't reach systemd-resolved's
    # socket from in here either, so name resolution fails ~100% (Prowlarr indexer
    # tests, Radarr SkyHook, Seerr all surface it as "Resource temporarily
    # unavailable" / EAI_AGAIN). Bind-mounting the netns resolv.conf over
    # /etc/resolv.conf makes each unit query the resolver that actually works.
    # (Proven live: FlareSolverr's Chromium went from 100% ERR_NAME_NOT_RESOLVED
    # to resolving once bound; the glibc *arrs behave the same.) The
    # single-request-reopen option appended above now applies to them too.
    (lib.genAttrs ["qbittorrent" "prowlarr" "sonarr" "radarr"]
      (_: {
        # Recycle each confined service whenever the netns (mullvad.service) is
        # restarted. VPN-Confinement already sets BindsTo=mullvad (stop-when-
        # mullvad-stops) + After=mullvad, but NOT PartOf — so a bare
        # `systemctl restart mullvad`, or the netns churn a deploy causes when it
        # restarts mullvad, tears the namespace down and re-creates it WITHOUT
        # bringing these back up cleanly. The .NET *arrs are the ones that bite:
        # if they keep running (or restart racing the fresh, not-yet-warm tunnel)
        # their SocketsHttpHandler pool caches the EAI_AGAIN/`Resource temporarily
        # unavailable` failure and they 503 indefinitely — Radarr's SkyHook
        # lookups fail, so a Seerr "remove request" gets a 503 back and hangs, and
        # Prowlarr indexer tests error — until someone manually restarts them.
        # `PartOf=mullvad.service` propagates mullvad's restart to them; the
        # existing `After=mullvad.service` (mullvad only goes active after its
        # ExecStartPost writes resolv.conf above) keeps them ordered so they come
        # back only once the netns resolver is in place. Byparr already gets this
        # via its Podman `--network=ns:` wiring (ConsistsOf=mullvad).
        partOf = ["mullvad.service"];

        serviceConfig.BindReadOnlyPaths = [
          "/etc/netns/${ns}/resolv.conf:/etc/resolv.conf"
          # Bypass systemd-resolved (nss-resolve) so `dns` → the netns resolv.conf
          # (10.64.0.1) is actually used — see nsswitchConf above. Without this the
          # resolv.conf bind is inert (nss-resolve short-circuits it).
          "${nsswitchConf}:/etc/nsswitch.conf"
        ];
      }))
  ];
}
