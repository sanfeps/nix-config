{
  inputs,
  lib,
  pkgs,
  ...
}: {
  imports = [inputs.noctalia-shell.homeModules.default];

  programs.noctalia-shell = {
    enable = true;
    package = inputs.noctalia-shell.packages.${pkgs.system}.default;
  };

  home.persistence."/persist".directories = [
    ".config/noctalia"
    ".cache/noctalia"
  ];

  home.activation.noctaliaSeedSettings = lib.hm.dag.entryAfter ["writeBoundary"] ''
    if [ ! -e "$HOME/.config/noctalia/settings.json" ]; then
      run mkdir -p "$HOME/.config/noctalia"
      run install -m644 ${./noctalia-settings.json} "$HOME/.config/noctalia/settings.json"
    fi
  '';
}
