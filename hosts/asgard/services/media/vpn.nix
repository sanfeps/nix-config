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

  # Caching DNS forwarder that runs INSIDE the netns and fronts Mullvad's
  # in-tunnel resolver (10.64.0.1). The confined services query it at 127.0.0.1
  # (see the resolv.conf rewrite + the ${ns}-dnsmasq service below) so repeated
  # lookups are answered from cache instead of racing the lossy single-resolver
  # tunnel path every time. `use-stale-cache` serves an expired answer when the
  # upstream momentarily can't be reached (the exact transient that used to
  # poison the .NET pools); `filter-AAAA` drops IPv6 answers (IPv4-only, which is
  # what servarr itself recommends for this failure mode); `no-resolv` keeps its
  # own upstream fixed at 10.64.0.1 regardless of what the netns resolv.conf says.
  dnsmasqConf = pkgs.writeText "${ns}-dnsmasq.conf" ''
    port=53
    listen-address=127.0.0.1
    bind-interfaces
    no-resolv
    no-hosts
    no-poll
    server=10.64.0.1
    cache-size=1000
    filter-AAAA
    use-stale-cache=86400
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

  # Harden DNS resolution inside the namespace. VPN-Confinement writes
  # /etc/netns/${ns}/resolv.conf with just the single Mullvad resolver
  # (10.64.0.1) and its firewall drops UDP/53 to anything else (leak belt), so we
  # can't add a fallback nameserver. That single lossy tunnel-routed resolver is
  # the root of the whole stack's flakiness: over the tunnel a reply
  # intermittently gets dropped, getaddrinfo returns EAI_AGAIN, and every confined
  # .NET app caches the failure in its SocketsHttpHandler pool → 503s until
  # restarted (Prowlarr indexers, Radarr SkyHook, Seerr requests marked FAILED).
  # `single-request-reopen` + the warm-tunnel gate only papered over it. The real
  # fix (below): point the netns resolv.conf at a local caching dnsmasq
  # (127.0.0.1) that fronts 10.64.0.1 — so repeated lookups hit cache, transient
  # upstream drops are covered by use-stale-cache, and AAAA is filtered. mullvad-up
  # does `rm -rf /etc/netns/${ns}` on every (re)start, so we rewrite it here.
  systemd.services = lib.mkMerge [
    {
      ${ns}.serviceConfig.ExecStartPost = lib.mkAfter [
        (pkgs.writeShellScript "${ns}-resolv-dnsmasq" ''
          printf 'nameserver 127.0.0.1\noptions single-request-reopen no-aaaa\n' \
            > /etc/netns/${ns}/resolv.conf
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

    # In-netns caching DNS forwarder (config in dnsmasqConf above). Confined to
    # the netns so it can reach 10.64.0.1 over the tunnel; the *arrs point their
    # resolv.conf at its 127.0.0.1 listener. partOf+after mullvad so it recycles
    # with the netns, and the confined services order after it (below). Binds the
    # privileged :53 via an ambient CAP_NET_BIND_SERVICE under DynamicUser.
    {
      "${ns}-dnsmasq" = {
        description = "Caching DNS forwarder inside the ${ns} netns";
        after = ["${ns}.service"];
        partOf = ["${ns}.service"];
        wantedBy = ["multi-user.target"];
        vpnConfinement = {
          enable = true;
          vpnNamespace = ns;
        };
        serviceConfig = {
          ExecStart = "${pkgs.dnsmasq}/bin/dnsmasq -k --conf-file=${dnsmasqConf}";
          Restart = "on-failure";
          RestartSec = 2;
          DynamicUser = true;
          AmbientCapabilities = ["CAP_NET_BIND_SERVICE"];
          CapabilityBoundingSet = ["CAP_NET_BIND_SERVICE"];
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
          NoNewPrivileges = true;
        };
      };
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

        # They now resolve via the in-netns dnsmasq (127.0.0.1), so order after it
        # — otherwise a service racing ahead at startup queries a dead resolver and
        # re-poisons its pool, exactly what we're trying to stop.
        after = ["${ns}-dnsmasq.service"];
        wants = ["${ns}-dnsmasq.service"];

        serviceConfig.BindReadOnlyPaths = [
          "/etc/netns/${ns}/resolv.conf:/etc/resolv.conf"
        ];
      }))
  ];
}
