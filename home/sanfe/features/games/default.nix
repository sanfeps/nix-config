{
  pkgs,
  config,
  ...
}: {
  imports = [
    ./steam.nix
    ./mangohud.nix
    ./sunshine.nix
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
