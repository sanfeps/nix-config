{
  config,
  lib,
  pkgs,
  ...
}:
# Phase 2 of the offsite plan (docs/immich-offsite-backup-plan.md §4): make
# draupnir a SEND-ONLY replication source that niflheim PULLS from.
#
# A dedicated unprivileged `syncoid` user holds ZFS `send,snapshot,bookmark,
# mount` delegation on the replicated datasets — and nothing else. No `destroy`,
# no `receive`, no `hold`: a compromise of niflheim (which holds this user's SSH
# key) can pull data but can NOT delete draupnir's snapshots or touch the pool.
# The incremental base is a zero-space BOOKMARK (via `bookmark` deleg + syncoid
# --create-bookmark), so an absent niflheim never bloats tank.
#
# INERT until niflheim exists: with no authorized key the user has no access,
# so this is safe to deploy now (it just pre-creates the user + delegation).
let
  user = "syncoid";
  datasets = ["tank/immich"];
  perms = "send,snapshot,bookmark,mount";
in {
  users.groups.${user} = {};
  users.users.${user} = {
    isSystemUser = true;
    group = user;
    home = "/var/lib/syncoid";
    createHome = true;
    shell = pkgs.bashInteractive; # niflheim runs `zfs …` over this ssh login

    # TODO(niflheim): niflheim's dedicated replication PUBLIC key. Generate a
    # keypair (NOT a host key):
    #   ssh-keygen -t ed25519 -C syncoid@niflheim -f ./niflheim-syncoid -N ""
    # Private half → niflheim sops (syncoid/ssh-key); public half → here.
    # Empty list = inert (no access) until then.
    openssh.authorizedKeys.keys = [
      # "ssh-ed25519 AAAA… syncoid@niflheim"   # TODO(niflheim)
    ];
  };

  # Delegate the minimal ZFS perms, re-asserted each boot (idempotent). `zfs
  # allow` persists in the pool, but declaring it keeps it in sync with config
  # and self-heals after a pool re-create.
  systemd.services.syncoid-zfs-allow = {
    description = "Delegate send-only ZFS perms to the ${user} user";
    after = ["zfs-import.target" "zfs.target"];
    wants = ["zfs.target"];
    wantedBy = ["multi-user.target"];
    path = [pkgs.zfs];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = lib.concatMapStringsSep "\n" (ds: "zfs allow ${user} ${perms} ${ds}") datasets;
  };
}
