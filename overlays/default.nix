{
  outputs,
  inputs,
}: let
in {
  # For every flake input, aliases 'pkgs.inputs.${flake}' to
  # 'inputs.${flake}.packages.${pkgs.system}' or
  # 'inputs.${flake}.legacyPackages.${pkgs.system}'

   # Adds pkgs.stable == inputs.nixpkgs-stable.legacyPackages.${pkgs.system}
   
   # Adds my custom packages

    # Modifies existing packages
   }
