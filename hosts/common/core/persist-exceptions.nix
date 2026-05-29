{
  config,
  lib,
  pkgs,
  ...
}: let
  users = lib.attrValues config.users.users;
  persistedHomes =
    map (user: "${config.hostSpec.persistFolder}${user.home}")
    (builtins.filter (user: user.createHome) users);
  find = lib.getExe' pkgs.findutils "find";
  rm = lib.getExe' pkgs.coreutils "rm";
in {
  systemd.services.direnv-cleanup = {
    description = "Remove persisted .direnv directories before user sessions";
    wantedBy = ["multi-user.target"];
    after = ["local-fs.target"];
    before = [
      "display-manager.service"
      "greetd.service"
      "systemd-user-sessions.service"
    ];
    serviceConfig.Type = "oneshot";
    script = lib.concatLines (
      map (persistedHome: ''
        if [ -d ${lib.escapeShellArg persistedHome} ]; then
          ${find} ${lib.escapeShellArg persistedHome} -type d -name .direnv -prune \
            -exec ${rm} -rf -- '{}' +
        fi
      '')
      persistedHomes
    );
  };
}
