{
  imports = [
    ./ddns.nix
    ./headscale.nix
  ];

  services.njalla-ddns = {
    enable = true;
    records = ["headscale.valgrindr.net"];
  };
}
