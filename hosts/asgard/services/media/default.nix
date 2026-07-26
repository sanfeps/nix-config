{
  imports = [
    ./vpn.nix
    ./storage.nix
    ./qbittorrent.nix
    ./prowlarr.nix
    ./sonarr.nix
    ./radarr.nix
    # ./flaresolverr.nix  # superseded by byparr.nix (FlareSolverr 3.5.0 can't
    #                       solve current Cloudflare); file kept for reference.
    ./byparr.nix
    ./music-dl.nix
    ./yt2jelly-ui.nix
    ./seerr.nix
    ./recyclarr.nix
    ./bootstrap.nix
    ./caddy.nix
  ];
}
