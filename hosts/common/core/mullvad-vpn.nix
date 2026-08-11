{
  config,
  pkgs,
  lib,
  ...
}: {
  services.resolved.enable = true;
  # nixpkgs split the package: `pkgs.mullvad-vpn` is now GUI-only and no longer
  # ships the daemon, so pinning `package` to it fails the module's assertion.
  # Leave `package` at its default (the daemon) and opt into the GUI separately.
  services.mullvad-vpn = {
    enable = true;
    gui.enable = true;
  };
}
