{
  imports = [
    ./caddy.nix
    ./finances
    ./home-automation
    # TODO(nas): uncomment once the NAS is provisioned and /mnt/nas/immich
    # mounts cleanly. See ./immich.nix for the activation checklist.
    # ./immich.nix

    # TODO(media): uncomment once `media/mullvad-wg-conf` is populated in
    # hosts/asgard/secrets.yaml. The VPN namespace comes up immediately;
    # subsequent phases add per-service modules (qbittorrent, *arrs, jellyfin,
    # seerr, recyclarr) and finally the NAS mount in ./media/storage.nix.
    # See ./media/vpn.nix for the bootstrap procedure.
    # ./media
  ];
}
