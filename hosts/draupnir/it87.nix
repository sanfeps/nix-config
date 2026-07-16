# Out-of-tree it87 hwmon driver (frankcrawford fork) for the ITE IT8613E fan
# controller on the DXP4800 Plus — mainline it87 doesn't know this chip.
# Consumed by ./fan-control.nix via boot.extraModulePackages.
{
  stdenv,
  lib,
  fetchFromGitHub,
  kernel,
}:
stdenv.mkDerivation {
  pname = "it87";
  version = "unstable-2026-04-12-${kernel.version}";

  src = fetchFromGitHub {
    owner = "frankcrawford";
    repo = "it87";
    rev = "20f2f2f4c92c14fcdd26f60d050e693ad2c30bf8";
    hash = "sha256-o2riPbm75Bez4/SrGV7hB3mlqdxxrwRPdre+3W5y/I0=";
  };

  hardeningDisable = ["pic"];
  nativeBuildInputs = kernel.moduleBuildDependencies;

  makeFlags = [
    "TARGET=${kernel.modDirVersion}"
    "KERNEL_MODULES=${kernel.dev}/lib/modules/${kernel.modDirVersion}"
    "KERNEL_BUILD=${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"
  ];

  installPhase = ''
    runHook preInstall
    install -D it87.ko $out/lib/modules/${kernel.modDirVersion}/kernel/drivers/hwmon/it87.ko
    runHook postInstall
  '';

  meta = {
    description = "it87 hwmon driver fork with IT8613E support";
    homepage = "https://github.com/frankcrawford/it87";
    license = lib.licenses.gpl2Plus;
    platforms = lib.platforms.linux;
  };
}
