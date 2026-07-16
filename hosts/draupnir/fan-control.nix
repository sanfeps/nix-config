# Fan/temperature visibility for the DXP4800 Plus (ITE IT8613E).
# Pattern proven on this exact hardware by github.com/daskladas/nasdots.
#
# This loads the driver so sensors + pwm knobs exist. An actual fan curve
# (hardware.fancontrol) is deliberately NOT configured yet: pwmconfig needs
# to be run on the live box first to learn the pwm/temp mapping. TODO after
# first boot. Until then the EC's default behavior drives the fans.
{
  config,
  pkgs,
  ...
}: {
  boot.extraModulePackages = [
    (pkgs.callPackage ./it87.nix {kernel = config.boot.kernelPackages.kernel;})
  ];
  boot.kernelModules = ["it87"];
  # force_id: the IT8613E answers with an ID the driver doesn't probe by
  # default; ignore_resource_conflict + acpi_enforce_resources=lax because
  # the UGREEN firmware claims the SuperIO region via ACPI.
  boot.extraModprobeConfig = ''
    options it87 force_id=0x8613 ignore_resource_conflict=1
  '';
  boot.kernelParams = ["acpi_enforce_resources=lax"];

  environment.systemPackages = [pkgs.lm_sensors];
}
