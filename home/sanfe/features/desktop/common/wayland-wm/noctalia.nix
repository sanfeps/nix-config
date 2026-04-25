{
  inputs,
  pkgs,
  ...
}: {
  imports = [inputs.noctalia-shell.homeModules.default];

  programs.noctalia-shell = {
    enable = true;
    package = inputs.noctalia-shell.packages.${pkgs.system}.default;
  };
}
