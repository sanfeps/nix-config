{
  inputs,
  config,
  lib,
  ...
}: let
  isEd25519 = k: k.type == "ed25519";
  keys = builtins.filter isEd25519 config.services.openssh.hostKeys;
  hostName = config.networking.hostName;
  username = config.hostSpec.username;
  perHostSecrets = ../../${hostName}/secrets.yaml;
  commonSecrets = ../secrets.yaml;
  isWorkstation = config.hostSpec.profile == "workstation";

  # Key names in sops files are stored in cleartext (only values are encrypted),
  # so a substring scan over the encrypted file is enough to know whether the
  # primary user's age key has been seeded. This lets workstations opt into
  # auto-bootstrap simply by populating user-age-keys/<user> in the shared
  # secrets file — no extra config toggle is needed.
  userAgeAvailable =
    builtins.pathExists commonSecrets
    && lib.strings.hasInfix "user-age-keys" (builtins.readFile commonSecrets);
  userAgeBootstrap = isWorkstation && userAgeAvailable;

  userHome = "/home/${username}";
  ageDir = "${userHome}/.config/sops/age";
in {
  imports = [inputs.sops-nix.nixosModules.sops];

  sops = {
    defaultSopsFile =
      if builtins.pathExists perHostSecrets
      then perHostSecrets
      else commonSecrets;
    age.sshKeyPaths = map (k: k.path) keys;

    secrets = lib.optionalAttrs userAgeBootstrap {
      "user-age-keys/${username}" = {
        sopsFile = commonSecrets;
        owner = username;
        group = "users";
        mode = "0400";
        path = "${ageDir}/keys.txt";
      };
    };
  };

  # sops-nix writes the secret at the absolute path with the requested owner,
  # but the parent directories are created as root. Fix ownership so the user
  # can write the rest of ~/.config without "Permission denied" later.
  system.activationScripts.sopsUserAgeOwnership = lib.mkIf userAgeBootstrap ''
    mkdir -p ${ageDir}
    chown -R ${username}:users ${userHome}/.config
  '';
}
