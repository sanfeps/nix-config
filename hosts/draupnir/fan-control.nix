# Fan control for the DXP4800 Plus (ITE IT8613E).
# Driver pattern proven on this exact hardware by github.com/daskladas/nasdots.
#
# Calibration (2026-07-16, sysfs sweep on the live box):
#   pwm2 -> fan2  CPU fan   (duty 70 = 1196 RPM, 130 = 2122, 255 = 3461)
#   pwm3 -> fan3  case fan  (duty 70 =  655 RPM, 130 = 1062, 255 = 1785)
#   pwm4/pwm5     unused headers (no tach response)
# Both fans spin reliably at the chip-auto idle duty of 51.
#
# The curve is a small loop service instead of hardware.fancontrol on purpose:
# fancontrol pins hwmon devices by sysfs path, and the drivetemp devices embed
# SATA enumeration that shuffles between boots (see disko-data.nix) — a path
# mismatch makes fancontrol refuse to start. This loop re-discovers sensors by
# name every tick, so renumbering can't break it. If the service stops or
# dies, the chip is put back in its own auto mode (enable=2), the same
# firmware behavior the box ran on before this existed.
{
  config,
  pkgs,
  ...
}: let
  it87Hwmon = ''
    find_hwmon() {
      for d in /sys/class/hwmon/hwmon*; do
        [ "$(cat "$d/name" 2>/dev/null)" = "$1" ] && { echo "$d"; return 0; }
      done
      return 1
    }
  '';

  fanCurve = pkgs.writeShellScript "draupnir-fan-curve" ''
    set -u
    ${it87Hwmon}
    it87=$(find_hwmon it8613) || { echo "it8613 hwmon not found" >&2; exit 1; }

    # curve TEMP_MILLI TMIN_C TMAX_C MINDUTY -> duty (linear, clamped)
    curve() {
      local t=$(($1 / 1000)) tmin=$2 tmax=$3 mind=$4
      if [ "$t" -le "$tmin" ]; then echo "$mind"
      elif [ "$t" -ge "$tmax" ]; then echo 255
      else echo $((mind + (t - tmin) * (255 - mind) / (tmax - tmin)))
      fi
    }

    echo 1 > "$it87/pwm2_enable"
    echo 1 > "$it87/pwm3_enable"

    while :; do
      cpu=45000
      c=$(find_hwmon coretemp) && cpu=$(cat "$c/temp1_input")

      # hottest drive across all drivetemp hwmons; if none readable,
      # assume warm (40C) rather than idling the case fan blind
      drive=0
      for d in /sys/class/hwmon/hwmon*; do
        if [ "$(cat "$d/name" 2>/dev/null)" = "drivetemp" ]; then
          t=$(cat "$d/temp1_input" 2>/dev/null || echo 0)
          [ "$t" -gt "$drive" ] && drive=$t
        fi
      done
      [ "$drive" -eq 0 ] && drive=40000

      # CPU fan: quiet <=45C, full at 80C. Case fan: drives quiet <=32C,
      # full at 48C (spinners should stay well under 45C).
      curve "$cpu" 45 80 52 > "$it87/pwm2"
      curve "$drive" 32 48 64 > "$it87/pwm3"
      sleep 20
    done
  '';

  fanRestore = pkgs.writeShellScript "draupnir-fan-restore" ''
    ${it87Hwmon}
    it87=$(find_hwmon it8613) || exit 0
    echo 2 > "$it87/pwm2_enable" 2>/dev/null || true
    echo 2 > "$it87/pwm3_enable" 2>/dev/null || true
  '';
in {
  boot.extraModulePackages = [
    (pkgs.callPackage ./it87.nix {kernel = config.boot.kernelPackages.kernel;})
  ];
  # drivetemp exposes SATA drive temps as hwmon sensors for the case-fan curve.
  boot.kernelModules = ["it87" "drivetemp"];
  # force_id: the IT8613E answers with an ID the driver doesn't probe by
  # default; ignore_resource_conflict + acpi_enforce_resources=lax because
  # the UGREEN firmware claims the SuperIO region via ACPI.
  boot.extraModprobeConfig = ''
    options it87 force_id=0x8613 ignore_resource_conflict=1
  '';
  boot.kernelParams = ["acpi_enforce_resources=lax"];

  environment.systemPackages = [pkgs.lm_sensors];

  systemd.services.fan-curve = {
    description = "Temperature-driven fan curve (it8613: pwm2=CPU, pwm3=case)";
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      ExecStart = fanCurve;
      # Hand the fans back to the chip's auto mode on stop/crash.
      ExecStopPost = fanRestore;
      Restart = "always";
      RestartSec = 10;
    };
  };
}
