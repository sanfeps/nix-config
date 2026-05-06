{pkgs, ...}: {
  imports = [
    ./common/core
    ./features/desktop/hyprland
    ./features/desktop/niri
    ./features/desktop/theming
    ./features/games
    ./features/cli
  ];

  home.sessionVariables = {
    LIBVA_DRIVER_NAME = "nvidia";
    __GLX_VENDOR_LIBRARY_NAME = "nvidia";
    NVD_BACKEND = "direct";
  };

  monitors = [
    {
      name = "DP-1";
      width = 5120;
      height = 1440;
      refreshRate = 240;
      workspace = "1";
      primary = true;
    }
  ];
}
