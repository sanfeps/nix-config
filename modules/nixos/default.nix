{
  # satisfactory = import ./satisfactory.nix;
  # hydra-auto-upgrade = import ./hydra-auto-upgrade.nix;
  # openrgb = import ./openrgb.nix;

  # Container services
  ghostfolio = import ./services/containers/ghostfolio.nix;
  headplane = import ./services/containers/headplane.nix;
  yamtrack = import ./services/containers/yamtrack.nix;

  # Shared infrastructure
  caddy-njalla = import ./services/caddy-njalla.nix;
}
