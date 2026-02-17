{
  config,
  pkgs,
  lib,
  ...
}: {
  services.resolved.enable = true;
  services.mullvad-vpn = {
    enable = true;
    package = pkgs.mullvad-vpn;
  };
}
