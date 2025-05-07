{pkgs, config, ...}: {
  imports = [
    ./steam.nix
    ./mangohud.nix
  ];
  home = {
    packages = with pkgs; [gamescope];
    persistence = {
      "${config.hostSpec.persistFolder}/${config.home.homeDirectory}" = {
        allowOther = true;
        directories = [
          "Games"
        ];
      };
    };
  };
}
