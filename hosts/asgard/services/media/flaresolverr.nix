{...}:
# FlareSolverr — Cloudflare / DDoS-Guard challenge solver for Prowlarr.
#
# Some public indexers sit behind Cloudflare's anti-bot JS challenge, which
# Prowlarr can't solve on its own. FlareSolverr runs a headless browser: Prowlarr
# hands it the challenged request, it passes the challenge and returns the
# cookies + user-agent for Prowlarr to reuse. (Dev has stalled upstream; if it
# starts timing out on newer Cloudflare, Byparr is the drop-in replacement —
# same :8191 API — but it's not in nixpkgs, so it'd be a Podman container here.)
#
# CONFINED to the Mullvad netns — this is load-bearing, not optional:
# FlareSolverr makes the ACTUAL outbound request to the indexer (it drives the
# browser), not Prowlarr. Run it outside the tunnel and the indexer sees
# asgard's real WAN IP — leaking straight past the VPN and defeating the whole
# netns design. In the namespace it egresses only through WireGuard (kill-switch
# by construction, same as qbittorrent/the *arrs).
#
# NO external ingress: FlareSolverr is an API-only proxy with no WebUI worth
# exposing, and its only client is Prowlarr, which lives in the SAME netns and
# reaches it at http://127.0.0.1:8191 (namespace loopback — exactly how
# Sonarr/Radarr reach qBittorrent). So unlike every other service in this stack
# there is deliberately NO Caddy vhost, NO AdGuard rewrite, NO portMappings
# entry (nothing off-host connects, so no in-namespace veth INPUT rule is
# needed), and NO firewall hole.
#
# Wiring it up (runtime, in the Prowlarr UI — not declared in Nix):
#   Settings → Indexers → Indexer Proxies → + → FlareSolverr
#     Host: http://127.0.0.1:8191   Tags: cloudflare
#   Then tag each Cloudflare-protected indexer with `cloudflare`; only tagged
#   indexers route through the proxy. Bump the indexer request timeout to ~180s
#   (browser challenges are slow). See media/CLAUDE.md.
let
  port = 8191;
in {
  services.flaresolverr = {
    enable = true;
    openFirewall = false; # no LAN hole; only same-netns Prowlarr reaches it on loopback.
    inherit port;
  };

  # Confine the systemd unit to the Mullvad netns. `mullvad.service` is the sole
  # writer of the namespace (vpn.nix); this just joins the unit to it.
  systemd.services.flaresolverr.vpnConfinement = {
    enable = true;
    vpnNamespace = "mullvad";
  };

  # DNS fix for the browser. Confined services see /etc/resolv.conf =
  # 127.0.0.53 (the host's systemd-resolved stub). The glibc-based *arrs still
  # resolve because nss-resolve talks to systemd-resolved over its UNIX socket,
  # which VPN-Confinement routes across the netns boundary. But FlareSolverr's
  # Chromium uses its OWN resolver: it reads resolv.conf and sends UDP straight
  # to 127.0.0.53 — a dead address INSIDE the netns — so every request dies with
  # net::ERR_NAME_NOT_RESOLVED. Bind the netns's own resolv.conf (nameserver
  # 10.64.0.1, the Mullvad resolver reachable over the tunnel) over
  # /etc/resolv.conf so Chromium queries a resolver it can actually reach. The
  # file is created by mullvad.service before this unit starts (vpnConfinement
  # orders after it).
  systemd.services.flaresolverr.serviceConfig.BindReadOnlyPaths = [
    "/etc/netns/mullvad/resolv.conf:/etc/resolv.conf"
  ];
}
