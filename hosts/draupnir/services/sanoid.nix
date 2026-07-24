{...}:
# Sanoid — automatic ZFS snapshots. Local fat-finger/bug protection only:
# snapshots live on the same pool, so they do NOT cover 2-disk failure,
# fire or theft — that's the (pending) offsite replication's job.
#
# Only tank/immich is snapshotted, deliberately:
#   - tank/media: re-downloadable by the *arrs and high-churn (imports
#     replace files constantly) — snapshots would pin deleted releases for
#     months with no recovery value.
#   - tank/backups: future restic target; restic versions itself, and
#     snapshotting a pruning repo mostly retains garbage.
#
# tank/immich is append-mostly (photos rarely change), so retention is
# cheap: the space cost is roughly "what you deleted, kept a while longer".
# The Immich nightly DB dumps land inside this dataset
# (<mediaLocation>/backups, see immich.nix), so every snapshot is a
# complete restore point: originals + a ≤24h database dump.
#
# Recover a file: /tank/immich/.zfs/snapshot/<name>/…  (read-only, always
# there — no mount step needed).
{
  services.sanoid = {
    enable = true; # 15-min systemd timer; sanoid decides what's due

    # Shared retention policy for anything hand-curated/irreplaceable.
    # Rolling windows = recovery granularity: any hour of the last day,
    # any day of the last month, any month of the last year.
    templates.irreplaceable = {
      autosnap = true;
      autoprune = true;
      hourly = 24;
      daily = 30;
      monthly = 12;
      # Yearlies are created here so the offsite copy (niflheim) can *receive*
      # them — its prune can only keep snapshot types the source makes, it
      # can't mint a yearly from a monthly. draupnir keeps a modest 3; niflheim
      # holds 10 (deep archive). See docs/immich-offsite-backup-plan.md §4.
      yearly = 3;
    };

    # New irreplaceable dataset later (docs, etc.)? `zfs create` it, add it
    # to disko-data.nix, then one line here.
    datasets."tank/immich".useTemplate = ["irreplaceable"];
  };
}
