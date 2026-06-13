{...}:
# Ingress for the whole media stack (per-host-caddy Phase 4). asgard's own
# Caddy (services.caddyNjalla, wildcard LE via Njalla DNS-01) terminates TLS
# for all six WebUIs; bifrost is no longer in the request path. The old
# bifrost media-proxies.nix is gone.
#
# Two reverse-proxy target classes:
#
#   * Unconfined (Jellyfin, Seerr) — live in asgard's main netns, bind 0.0.0.0,
#     so Caddy reaches them on 127.0.0.1:<port>.
#
#   * Confined (qBittorrent, Prowlarr, Sonarr, Radarr) — live in the Mullvad
#     netns. Caddy is in the MAIN netns, so it CANNOT use 127.0.0.1: the
#     VPN-Confinement PREROUTING DNAT (host:<from> → ns) only fires for
#     incoming/forwarded connections, never for host-local loopback. Instead
#     Caddy talks straight to the namespace veth IP `192.168.15.1:<port>` over
#     the `mullvad-br` bridge (host side 192.168.15.5/24). The per-service
#     `vpnNamespaces.mullvad.portMappings` entry is what installs the
#     in-namespace `-A INPUT -i veth-mullvad --dport <port> -j ACCEPT` rule
#     that permits exactly this hop — so those portMappings stay declared even
#     though their host-side DNAT half is now unused.
let
  nsIp = "192.168.15.1"; # vpnNamespaces.mullvad.namespaceAddress (default)
  vhost = name: target: {
    "${name}.lan.valgrindr.net".extraConfig = "reverse_proxy ${target}";
  };
in {
  services.caddy.virtualHosts =
    # Unconfined — host loopback.
    (vhost "jellyfin" "127.0.0.1:8096")
    // (vhost "seerr" "127.0.0.1:5055")
    # Confined — Mullvad netns veth IP.
    // (vhost "qbittorrent" "${nsIp}:8080")
    // (vhost "prowlarr" "${nsIp}:9696")
    // (vhost "sonarr" "${nsIp}:8989")
    // (vhost "radarr" "${nsIp}:7878");
}
