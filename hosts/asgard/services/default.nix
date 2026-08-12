{
  imports = [
    ./caddy.nix

    # Shared PostgreSQL instance + the instance-wide dump timer. Lives here,
    # not under ./finances, because it is host infrastructure: several
    # unrelated app domains (finances, yamtrack, …) keep their databases on
    # this one server, and backups.nix dumps every database on it.
    ./postgresql

    ./finances
    ./home-automation

    # Media/book tracker (films + books watch/read log). Its backup path —
    # the CSV export + the NAS copy — lives in ./appdata-backup.nix.
    ./yamtrack.nix
    ./appdata-backup.nix

    # TODO(media): uncomment once `media/mullvad-wg-conf` is populated in
    # hosts/asgard/secrets.yaml. The VPN namespace comes up immediately;
    # subsequent phases add per-service modules (qbittorrent, *arrs, jellyfin,
    # seerr, recyclarr) and finally the NAS mount in ./media/storage.nix.
    # See ./media/vpn.nix for the bootstrap procedure.
    ./media

    # Fluxer (self-hosted chat). Requires the `fluxer/*` sops secrets in
    # hosts/asgard/secrets.yaml — see ./fluxer/CLAUDE.md for ops/bootstrap.
    #./fluxer
  ];
}
