{
  # Reusable homelab service modules (homelab.services.*). Native-NixOS-service
  # counterpart to modules/nixos/services/containers/*. Merged into
  # outputs.nixosModules in flake.nix, so every entry here auto-loads on every
  # host and must be inert until its `enable` flag flips.
  #
  # See docs/services-reusable-modules-plan.md for the design rationale.
  immich = import ./services/immich;
  home-assistant = import ./services/home-assistant;
}
