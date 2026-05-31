{
  imports = [
    ./caddy.nix
    ./finances
    ./home-automation
    # TODO(nas): uncomment once the NAS is provisioned and /mnt/nas/immich
    # mounts cleanly. See ./immich.nix for the activation checklist.
    # ./immich.nix
  ];
}
