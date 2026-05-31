{
  imports = [
    ./caddy.nix
    ./finances
    ./home-automation
    ./immich.nix

    # TODO(media): uncomment once `media/mullvad-wg-conf` is populated in
    # hosts/asgard/secrets.yaml. The VPN namespace comes up immediately;
    # subsequent phases add per-service modules (qbittorrent, *arrs, jellyfin,
    # seerr, recyclarr) and finally the NAS mount in ./media/storage.nix.
    # See ./media/vpn.nix for the bootstrap procedure.
    ./media
  ];
}
