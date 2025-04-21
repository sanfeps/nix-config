{pkgs ? import <nixpkgs> {}, ...}: {
  default = pkgs.mkShell {
    NIX_CONFIG = "extra-experimental-features = nix-command flakes ca-derivations";
    nativeBuildInputs = with pkgs; [
      nix
      home-manager
      git

      sops
      ssh-to-age
      gnupg
      age
      mkpasswd
    ];

    shellHook = ''
	export SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt"
	echo "🔐 SOPS_AGE_KEY_FILE set!"
    '';
  };
}
