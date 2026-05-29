{
  config,
  pkgs,
  ...
}: let
  flyImport = pkgs.writers.writePython3Bin "fly-import" {
    libraries = with pkgs.python3Packages; [requests pdfplumber];
    flakeIgnore = ["E501" "W503"];
  } (builtins.readFile ./fly_import.py);
in {
  sops.secrets."finances/firefly-access-token" = {
    owner = config.hostSpec.username;
    mode = "0400";
  };

  environment.systemPackages = [flyImport];
}
