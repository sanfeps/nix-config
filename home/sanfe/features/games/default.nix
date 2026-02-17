{
  pkgs,
  config,
  ...
}: {
  imports = [
    ./steam.nix
    ./mangohud.nix
  ];
  home = {
    packages = with pkgs; [gamescope];
    persistence = {
      "/persist" = {
        directories = [
          "Games"
        ];
      };
    };
  };
}
