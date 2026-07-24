{...}:
# Prune-only sanoid. niflheim does NOT take its own snapshots — every snapshot
# on `cold/*` arrives via syncoid (raw receive) from draupnir. sanoid here only
# BOUNDS the received history.
#
# Retention is deliberately DEEPER than home and decoupled from it: syncoid only
# ever *adds* snapshots to `cold/*` and never propagates draupnir's deletions,
# so niflheim keeps whatever its own policy says. It holds 24 monthlies + 10
# yearlies even though draupnir keeps 12 + 3 — it received each while alive on
# the source and never deletes it. See docs/immich-offsite-backup-plan.md §4.
#
# The on-connect workflow (syncoid.nix) also runs `sanoid --prune-snapshots`
# explicitly before poweroff, so pruning is deterministic even though this
# module's 15-min timer would rarely get the chance to fire on an off-most-of-
# the-month box.
{
  services.sanoid = {
    enable = true;

    templates.offsite = {
      autosnap = false; # snapshots come from syncoid, never created here
      autoprune = true;
      hourly = 0; # no offsite value in sub-day granularity
      daily = 30; # ~a month, matches what survives on draupnir to be sent
      monthly = 24; # 2 years
      yearly = 10; # deep archive (draupnir only mints/keeps 3)
    };

    datasets."cold/immich".useTemplate = ["offsite"];
    datasets."cold/backups".useTemplate = ["offsite"];
  };
}
