{
  config,
  lib,
  pkgs,
  ...
}:
# Ship the app data that is NOT re-derivable from anything else to the NAS.
#
# Today that means Yamtrack: the list of films/books watched and read, and the
# ratings. The point of this file is the *list*, not the app — so the primary
# artifact is Yamtrack's own **CSV export** (portable, re-importable into any
# tracker, readable in a spreadsheet in 10 years), and the pg_dump is the
# belt-and-braces second copy.
#
# Two deliberate design choices:
#
#   1. **The dump timer stays instance-wide, this sync is allowlisted.**
#      hosts/asgard/services/postgresql/backups.nix dumps EVERY database on the
#      shared instance (cheap, local). Only the databases named below leave the
#      box. Adding another later (e.g. firefly-iii for the finance offsite) is
#      one entry in `databases`.
#
#   2. **Stable filenames, no rotation logic here.** Every artifact is written
#      to the same path each night. History is provided by draupnir's sanoid
#      snapshots of tank/appdata (24h/30d/12m/3y) — so "yesterday's CSV" is
#      /tank/appdata/.zfs/snapshot/<snap>/yamtrack/…, not a datestamped pile
#      that something has to prune. The offsite copy (niflheim) inherits the
#      same snapshots.
let
  nas = "/mnt/nas/appdata";
  exportDir = config.services.containers.yamtrack.exportDir;

  # Databases copied OFF the box. Everything else is still dumped locally by
  # postgresql/backups.nix — this list is only about what reaches the NAS.
  databases = ["yamtrack"];
  backupRoot = "/var/backups/postgres";

  # Runs inside the container. Yamtrack has no management command for this, so
  # we call the same function its download button calls
  # (src/integrations/exports.py :: generate_rows, which yields ready-made CSV
  # lines) — meaning this file is byte-identical to a UI export and re-importable
  # by Yamtrack itself. Doing it in-process avoids needing a session cookie or
  # an HTTP round-trip.
  exportScript = pkgs.writeText "yamtrack-export.py" ''
    import os
    import re

    from django.contrib.auth import get_user_model

    from integrations import exports

    outdir = "/exports"
    os.makedirs(outdir, exist_ok=True)

    exported = 0
    for user in get_user_model().objects.filter(is_active=True):
        safe = re.sub(r"[^A-Za-z0-9_.-]", "_", user.username)
        final = os.path.join(outdir, "yamtrack-%s.csv" % safe)
        tmp = final + ".tmp"
        # Write-then-rename: a crashed or truncated export must never replace
        # the last good CSV, because the snapshot could catch it mid-write.
        with open(tmp, "w", newline="") as fh:
            for row in exports.generate_rows(user):
                fh.write(row)
        os.replace(tmp, final)
        exported += 1
        print("exported %s" % final)

    if exported == 0:
        raise SystemExit("no active users found - nothing exported")
  '';

  backupScript = pkgs.writeShellApplication {
    name = "appdata-backup";
    runtimeInputs = with pkgs; [podman coreutils findutils util-linux];
    text = ''
      set -euo pipefail

      # ── 1. Refresh the CSV export ────────────────────────────────────────
      # Non-fatal on purpose: if Yamtrack is down we still want the pg_dump leg
      # to run and ship whatever CSV is already on disk.
      if podman exec yamtrack python manage.py shell -c "$(cat ${exportScript})"; then
        echo "csv export: ok"
      else
        echo "csv export: FAILED - shipping the previous CSV instead" >&2
      fi

      # ── 2. Verify the NAS is really mounted ──────────────────────────────
      # Critical guard, not paranoia: ${nas} is an automount, and writing into
      # the mountpoint while it is NOT mounted would silently fill asgard's
      # local disk — the exact path that took the Proxmox thin-pool to ENOSPC
      # and froze the VM into io-error (2026-07-27). Touch it first to trigger
      # the automount, then refuse to continue if it did not come up.
      ls "${nas}" >/dev/null 2>&1 || true
      if ! mountpoint -q "${nas}"; then
        echo "ERROR: ${nas} is not mounted - refusing to write to local disk" >&2
        exit 1
      fi

      install -d -m 0750 "${nas}/yamtrack" "${nas}/postgres"

      # ── 3. CSVs → NAS ────────────────────────────────────────────────────
      shopt -s nullglob
      for src in ${exportDir}/*.csv; do
        name=$(basename "$src")
        cp -- "$src" "${nas}/yamtrack/.$name.tmp"
        mv -- "${nas}/yamtrack/.$name.tmp" "${nas}/yamtrack/$name"
        echo "copied $name"
      done
      shopt -u nullglob

      # ── 4. Allowlisted pg_dumps → NAS ────────────────────────────────────
      # Bash array rather than a bare word list: with a single entry shellcheck
      # (which writeShellApplication runs as a build gate) rejects the literal
      # form as SC2043 "this loop will only ever run once".
      databases=(${lib.concatStringsSep " " databases})
      for db in "''${databases[@]}"; do
        # Newest dump for this database. `find -printf` + sort rather than
        # parsing `ls`, so the filename never has to be word-split.
        newest=$(find "${backupRoot}/$db" -maxdepth 1 -type f -name '*.dump' \
                   -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
        if [ -z "$newest" ]; then
          echo "WARNING: no dump found for database '$db' - has postgres-backup run yet?" >&2
          continue
        fi
        cp -- "$newest" "${nas}/postgres/.$db.dump.tmp"
        mv -- "${nas}/postgres/.$db.dump.tmp" "${nas}/postgres/$db.dump"
        echo "copied $db.dump (from $(basename "$newest"))"
      done

      echo "appdata backup complete"
    '';
  };
in {
  # NFSv4 automount of draupnir's tank/appdata. Same shape as the media mounts
  # (soft, _netdev) so a draupnir hiccup can't block boot. draupnir's export
  # squashes our root to its local appdata uid/gid 1501 — see that host's
  # services/nfs.nix for why this export needs anonuid/anongid and the media
  # ones don't.
  fileSystems.${nas} = {
    device = "192.168.1.56:/tank/appdata";
    fsType = "nfs";
    options = ["x-systemd.automount" "noauto" "_netdev" "soft" "timeo=30" "nfsvers=4.2"];
  };

  systemd.services.appdata-backup = {
    description = "Export Yamtrack list/ratings to CSV and copy app backups to the NAS";
    # Runs as root: needs the podman socket (containers are root units here) and
    # read access to /var/backups/postgres, which is 0700 postgres.
    serviceConfig = {
      Type = "oneshot";
      ExecStart = lib.getExe backupScript;
    };
  };

  systemd.timers.appdata-backup = {
    description = "Daily app-data backup to the NAS";
    wantedBy = ["timers.target"];
    timerConfig = {
      # 03:30, comfortably after postgres-backup (daily + up to 30min jitter),
      # so the dump this copies is the current night's, not yesterday's.
      OnCalendar = "03:30";
      Persistent = true;
      RandomizedDelaySec = "10min";
    };
  };
}
