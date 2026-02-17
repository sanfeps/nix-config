{
  inputs,
  lib,
  pkgs,
  config,
  outputs,
  ...
}: {
  imports =
    [
    ]
    ++ (builtins.attrValues outputs.homeManagerModules);

  nix = {
    package = lib.mkDefault pkgs.nix;
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
        "ca-derivations"
      ];
      warn-dirty = false;
    };
  };

  systemd.user.startServices = "sd-switch";

  programs = {
    home-manager.enable = true;
    git.enable = true;
  };

  home = {
    username = lib.mkDefault "sanfe";
    homeDirectory = lib.mkDefault "/home/${config.home.username}";
    sessionPath = ["$HOME/.local/bin"];
    stateVersion = "24.11";
    sessionVariables = {
      FLAKE = "$HOME/Documents/NixConfig";
    };

    persistence = {
      "/persist" = {
        directories = [
          "Documents"
          "Downloads"
          "Pictures"
          "Videos"
          ".local/bin"
          ".local/share/nix" # trusted settings and repl history

          # Projects
          "nix-config"

          # SSH and security
          ".ssh"
          ".pki"

          # Claude Code
          ".claude"

          # Shell and editor state
          ".vim"

          # Nix/HM state
          ".local/state/nix"
          ".local/state/home-manager"
          ".local/share/home-manager"

          # Desktop state
          ".config/dconf"
          ".config/Mullvad VPN"
          ".config/pulse"

          # Audio
          ".local/state/wireplumber"

          # Misc
          ".npm"
          ".npm-global"
          ".local/share/containers"
        ];
        files = [
          ".npmrc"
          ".claude.json"
        ];
      };
    };
  };

  home.packages = with pkgs; [
    wireguard-tools
  ];
}
