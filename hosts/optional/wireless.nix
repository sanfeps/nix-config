{
  config,
  lib,
  ...
}: {
  hardware.bluetooth = {
    enable = true;
  };

  networking.wireless = {
    enable = true;
    fallbackToWPA2 = false;
    networks = {
      #"Pixel_4058" = {
      #	psk = "dusqcvzyk3ra4pp";
      #};
      "MOVISTAR_45C0" = {
        psk = "v5374FwESUe3oue5U6rY";
      };
      #"MOVISTAR_7948" = {
      #	psk = "h973b77eM9AE7WN3Ub3W";
      #};
      "TP-Link_EF86" = {
	psk = "61107341";
      };
    };
  };
}
