{...}: {
  imports = [
    ./caddy.nix
    ./immich.nix
    ./nfs.nix
    ./sanoid.nix
    ./syncoid-source.nix
  ];
}
