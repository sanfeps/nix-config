{pkgs, ...}: {
  imports = [
    ./bat.nix
    ./fzf.nix
    ./nix-index.nix
    ./starship.nix
    ./zsh
  ];
  home.packages = with pkgs; [
    distrobox # Nice escape hatch, integrates docker images with my environment

    bottom # System viewer
    ncdu # TUI disk usage
    eza # Better ls
    ripgrep # Better grep
    fd # Better find
    httpie # Better curl
    jq # JSON pretty printer and manipulator

    nixd # Nix LSP
    alejandra # Nix formatter
    nixfmt
    nvd # Differ
    nix-diff # Differ, more detailed
    nix-output-monitor
    nh # Nice wrapper for NixOS and HM
  ];
}
