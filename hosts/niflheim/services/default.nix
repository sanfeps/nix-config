{
  imports = [
    ./sanoid.nix # prune-only retention of the received datasets
    ./syncoid.nix # the run-on-connect pull → prune → notify → poweroff workflow
  ];
}
