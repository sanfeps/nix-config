# General-purpose video player for the desktop. Primary job right now is
# reviewing captures from features/desktop/recording, which are 5120x1440 HEVC
# — software decoding those stutters, hence the hwdec settings below.
{...}: {
  programs.mpv = {
    enable = true;
    config = {
      # NVIDIA: goes through nvdec/vaapi (the LIBVA_DRIVER_NAME and NVD_BACKEND
      # session vars set in home/sanfe/midgard.nix). "auto-safe" only accepts
      # decoders known to be reliable, falling back to software rather than
      # rendering garbage.
      hwdec = "auto-safe";
      vo = "gpu-next";
      profile = "high-quality";

      # Don't close the window on the last frame — replay clips are short and
      # the default behaviour makes them vanish before you can look at them.
      keep-open = "yes";

      # Never open a window wider than the monitor: a 5120px-wide capture would
      # otherwise ask niri for a tile bigger than the output.
      autofit-larger = "80%x80%";
    };
  };
}
