{
  config,
  pkgs,
  ...
}: {
  programs.alacritty = {
    enable = true;

    settings = {
      general.import = [
        "${config.home.homeDirectory}/.local/state/quickshell/user/generated/alacritty-colors.toml"
      ];

      font = {
        normal.family = config.fontProfiles.monospace.name;
        size = config.fontProfiles.monospace.size;
        bold = {style = "Bold";};
      };

      window.padding = {
        x = 10;
        y = 10;
      };
    };
  };
}
