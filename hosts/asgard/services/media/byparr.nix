{...}:
# Byparr — modern Cloudflare-challenge solver for Prowlarr, replacing
# FlareSolverr. FlareSolverr 3.5.0 (the nixpkgs version) can no longer solve
# current Cloudflare challenges — it launches the browser, reaches the indexer,
# then times out after 60s ("Error solving the challenge"). Byparr uses a
# stealthier headless browser and passes. It speaks the same :8191 `/v1` API, so
# Prowlarr's existing FlareSolverr indexer-proxy (Settings → Indexers → Indexer
# Proxies, host http://127.0.0.1:8191, tag `cloudflare`) points at it unchanged.
#
# Not packaged in nixpkgs → runs as a Podman container (asgard already imports
# hosts/optional/podman.nix). Like FlareSolverr it makes the REAL request to the
# indexer, so it MUST egress through Mullvad or it leaks asgard's WAN IP. The
# container joins the existing `mullvad` netns via podman's `--network=ns:`
# (rather than VPN-Confinement, which only wraps systemd services), so its
# browser traffic goes through the tunnel. DNS is the netns resolver 10.64.0.1
# (the same one the confined *arrs use — see vpn.nix). No published ports: it
# lives inside the namespace, and Prowlarr (also in it) reaches it at
# http://127.0.0.1:8191 on the shared netns loopback.
{
  virtualisation.oci-containers.containers.byparr = {
    image = "ghcr.io/thephaseless/byparr:v2.1.0";
    extraOptions = [
      "--network=ns:/run/netns/mullvad" # egress through the Mullvad tunnel
      "--dns=10.64.0.1" # the netns (Mullvad) resolver
      "--shm-size=512m" # byparr's browser multiprocessing needs it
    ];
  };

  # Tie the container to the namespace: start only after mullvad.service has
  # created the netns, and restart with it — `mullvad-up` does `rm -rf` + a
  # fresh `ip netns add` on every (re)start, which invalidates the
  # `--network=ns:` reference, so the container must be recycled alongside it.
  systemd.services.podman-byparr = {
    after = ["mullvad.service"];
    requires = ["mullvad.service"];
    partOf = ["mullvad.service"];
  };
}
