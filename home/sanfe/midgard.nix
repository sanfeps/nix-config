{
  pkgs,
  ...
}: {
  imports = [
    ./common/core
    ./features/games
  ];

  #  ------   -----   ------
  # | DP-3 | | DP-1| | DP-2 |
  #  ------   -----   ------
  monitors = [
    {
      name = "DP-1";
      width = 2560;
      height = 1440;
      workspace = "1";
      primary = true;
    }
  ];
}
