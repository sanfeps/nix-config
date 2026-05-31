{
  # satisfactory = import ./satisfactory.nix;
  # hydra-auto-upgrade = import ./hydra-auto-upgrade.nix;
  # openrgb = import ./openrgb.nix;

  # Container services
  jellyfin = import ./services/containers/jellyfin.nix;
  ghostfolio = import ./services/containers/ghostfolio.nix;
  headplane = import ./services/containers/headplane.nix;
}
