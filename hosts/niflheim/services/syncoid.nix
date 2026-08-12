{
  config,
  lib,
  pkgs,
  ...
}:
# The offsite replication workflow. Runs ON CONNECT (every boot, once the
# network + tailnet are up), pulls draupnir's datasets raw, prunes the local
# copy, announces, and powers the box back off. Retries until it succeeds; if it
# stays broken for ~1h it pings ntfy so an on-but-stuck box gets noticed while
# someone's next to it. Design: docs/immich-offsite-backup-plan.md §4 + §6.
let
  # draupnir over the tailnet — NOT the LAN IP, since niflheim is usually
  # offsite. 100.64.0.13 avoids depending on MagicDNS; `draupnir` would also
  # work if accept-dns is on. TODO: confirm reachability at bring-up.
  remoteUser = "syncoid";
  remoteHost = "100.64.0.13";
  remote = "${remoteUser}@${remoteHost}";

  datasets = [
    {
      src = "tank/immich";
      dst = "cold/immich";
    }
    # App-state backups pushed to draupnir by asgard (Yamtrack watch/read list
    # + ratings: nightly CSV export + pg_dump). Tiny next to immich, so it adds
    # no meaningful time to the pull. Snapshotted on the source by draupnir's
    # sanoid — mandatory, since --no-sync-snap can only ship existing snapshots.
    {
      src = "tank/appdata";
      dst = "cold/appdata";
    }
  ];

  ntfyUrl = "https://ntfy.lan.valgrindr.net";
  ntfyTopic = "backup-niflheim"; # TODO(sops): create topic + publish token

  # TODO(sops): declare these once `&niflheim` is in .sops.yaml and the file is
  # created (`sops hosts/niflheim/secrets.yaml`):
  #   syncoid/ssh-key    — private key for syncoid@draupnir (send-only deleg)
  #   syncoid/ntfy-token — bearer token to publish to ${ntfyTopic}
  sshKey = config.sops.secrets."syncoid/ssh-key".path;
  ntfyToken = config.sops.secrets."syncoid/ntfy-token".path;

  syncScript = pkgs.writeShellApplication {
    name = "niflheim-offsite-sync";
    runtimeInputs = [pkgs.sanoid pkgs.zfs pkgs.openssh pkgs.curl pkgs.systemd];
    text = ''
      notify() { # $1=title  $2=priority  $3=body
        curl -fsS \
          -H "Authorization: Bearer $(cat ${ntfyToken})" \
          -H "Title: $1" -H "Priority: $2" \
          -d "$3" "${ntfyUrl}/${ntfyTopic}" || true
      }

      # One full pull of every dataset. Attempts all of them and reports failure
      # if ANY leg failed, so a partial pull is never mistaken for success.
      run_sync() {
        local ok=0
      ${lib.concatMapStringsSep "\n" (d: ''
        syncoid --no-sync-snap --create-bookmark --sendoptions=w \
          --sshkey=${sshKey} --sshoption=StrictHostKeyChecking=accept-new \
          "${remote}:${d.src}" "${d.dst}" || ok=1'')
      datasets}
        return "$ok"
      }

      start=$(date +%s)
      alerted=0

      # Retry until the whole pull goes through. `until` exempts run_sync from
      # `set -e`, so a failed leg loops instead of killing the script.
      until run_sync; do
        now=$(date +%s)
        if [ "$alerted" -eq 0 ] && [ $((now - start)) -gt 3600 ]; then
          notify "niflheim offsite: STILL FAILING" "high" \
            "syncoid has retried >1h without success — check draupnir reachability, the SSH key, or the cold pool."
          alerted=1
        fi
        sleep 300
      done

      # Success. Bound the local history (deterministic, before we power off),
      # announce, and shut down — copy #3 is current.
      sanoid --prune-snapshots --verbose || true
      notify "niflheim offsite: sync OK" "default" \
        "${lib.concatMapStringsSep ", " (d: d.dst) datasets} up to date at $(date -u +%FT%TZ). Powering off."
      systemctl poweroff
    '';
  };
in {
  # See TODO(sops) above — declared here so the module is complete, but the
  # secrets.yaml itself can't exist until &niflheim is a sops recipient.
  sops.secrets."syncoid/ssh-key" = {mode = "0400";};
  sops.secrets."syncoid/ntfy-token" = {mode = "0400";};

  # Run-on-connect: fire on every boot after the network + tailnet come up. The
  # script owns its own retry loop (so it can time the "still failing" alert);
  # Restart is a backstop for the script itself crashing. Runs as root — needs
  # `zfs receive`/bookmark on `cold` and `systemctl poweroff`.
  systemd.services.offsite-sync = {
    description = "Offsite ZFS replication pull from draupnir, then poweroff";
    after = ["network-online.target" "tailscaled.service"];
    wants = ["network-online.target"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "exec";
      ExecStart = lib.getExe syncScript;
      Restart = "on-failure";
      RestartSec = "5min";
    };
  };
}
