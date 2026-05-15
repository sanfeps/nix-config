{
  outputs,
  lib,
  ...
}: let
  hostnames = lib.attrNames outputs.nixosConfigurations;
  extraAliases = ["yggdrasil.lo" "git.yggdrasil.lo"];
in {
  programs.ssh = {
    enable = true;
    matchBlocks = {
      net = {
        host = lib.concatStringsSep " " (
          lib.flatten (map (h: [
              h
              "${h}.yggdrasil.lo"
              "${h}.ts.yggdrasil.lo"
            ])
            hostnames)
          ++ extraAliases
        );
        user = "sanfe";
        forwardAgent = true;
        identityFile = "~/.ssh/lykill";
        identitiesOnly = true;
      };
    };
  };
}
