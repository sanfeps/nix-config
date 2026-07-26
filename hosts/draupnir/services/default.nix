{...}: {
  imports = [
    ./caddy.nix
    ./immich.nix
    ./jellyfin.nix
    ./nfs.nix
    ./sanoid.nix
    ./syncoid-source.nix
  ];
}
