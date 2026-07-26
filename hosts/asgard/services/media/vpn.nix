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
  # (10.64.0.1) and its firewall drops UDP/53 to anything else (leak belt), so
  # we can't add a fallback nameserver. In a dual-stack netns glibc fires the A
  # and AAAA queries in parallel on one socket; over the tunnel one reply
  # intermittently gets dropped, so getaddrinfo returns EAI_AGAIN and every
  # confined .NET app surfaces it as `SocketException (11): Resource temporarily
  # unavailable (<host>:443)` — Prowlarr indexer tests fail, Radarr's SkyHook
  # metadata lookups 503, and Seerr marks the resulting request FAILED.
  # `single-request-reopen` makes glibc issue the two lookups sequentially on
  # separate sockets, which removes the dropped-reply race. mullvad-up does
  # `rm -rf /etc/netns/${ns}` on every (re)start, so re-append on ExecStartPost.
  systemd.services = lib.mkMerge [
    {
      ${ns}.serviceConfig.ExecStartPost = lib.mkAfter [
        (pkgs.writeShellScript "${ns}-resolv-single-request" ''
          printf 'options single-request-reopen\n' >> /etc/netns/${ns}/resolv.conf
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
    (lib.genAttrs ["qbittorrent" "prowlarr" "sonarr" "radarr" "flaresolverr"]
      (_: {
        serviceConfig.BindReadOnlyPaths = [
          "/etc/netns/${ns}/resolv.conf:/etc/resolv.conf"
        ];
      }))
  ];
}
