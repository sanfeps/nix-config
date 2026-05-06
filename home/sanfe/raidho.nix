{lib, ...}: {
  imports = [
    ./common/core
    ./features/desktop/niri
    ./features/desktop/theming
    ./features/cli
    ./features/games/moonlight.nix
  ];

  xdg.configFile."niri/config.kdl".source = lib.mkForce ./features/desktop/niri/raidho-config.kdl;
}
