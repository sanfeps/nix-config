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

          # Quickshell state + matugen generated colors
          ".local/state/quickshell"

          # Matugen wallpaper cache
          ".cache/matugen"

          # Wallpaper storage
          "Pictures/Wallpapers"
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

  home.file.".config/wireguard/wg0.conf" = {
    text = ''
      [Interface]
      PrivateKey = oFQE1ZVn9idpOZnqu+/+f+C7RRjKVkB/Hs/ICH1yEVQ=
      Address = 10.10.0.2/24

      [Peer]
      PublicKey = +wNa7J01GK/KQiTZ8i+BuXy117j1tAy6CN7ltGPBkyY=
      Endpoint = headscale.valgrindr.net:51820
      AllowedIPs = 10.10.0.0/24,192.168.1.0/24
      PersistentKeepalive = 25
    '';
    target = ".config/wireguard/wg0.conf";
  };
}
