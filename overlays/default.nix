{
  outputs,
  inputs,
}: {
  #stable = final: prev: {
  #  stable = inputs.nixpkgs-stable.legacyPackages.${prev.system};
  #};

  #quickshell = final: prev: {
  #	quickshell = inputs.quickshell.packages.${prev.stdenv.hostPlatform.system}.default;
  #};
  
}
