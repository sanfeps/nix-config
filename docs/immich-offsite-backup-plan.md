# Offsite backup plan — `tank/immich` (and `tank/backups`)

Status: **plan, not yet implemented.** Pairs with
`docs/immich-draupnir-migration-runbook.md` (the move that made draupnir the
*primary* home for the photos) and `docs/draupnir-disk-failure-runbook.md`
(which flags "2-drive loss / fire / theft loses everything" as the open risk
this plan closes).

## 1. Goal and scope

draupnir gives the photos **local** resilience — raidz1 (1-drive fault
tolerance) plus sanoid snapshots (`hosts/draupnir/services/sanoid.nix`,
template `irreplaceable`: 24h / 30d / 12m). What's missing is the **off-site
copy**: the one that survives a two-drive loss, pool-level corruption, fire,
theft, flood, or a `zfs destroy` fat-finger.

This is the third leg of 3-2-1:

| | Copy | Medium / location |
|---|---|---|
| 1 | live `tank` | draupnir, home |
| 2 | sanoid snapshots | same pool (fat-finger / ransomware time-travel — **not** a second location) |
| 3 | **this plan** | a second physical location |

**Scope — what replicates offsite:**

| Dataset | Offsite? | Rationale |
|---|---|---|
| `tank/immich` | **Yes** | Irreplaceable. Photos + the nightly Immich pg_dump that lives *inside* the dataset (`<mediaLocation>/backups`) → every snapshot is a self-contained restore point. |
| `tank/backups` | **Yes** | Small; finance restic repo + dumps. Cheap insurance. |
| `tank/media` | **No** | Re-downloadable by the *arrs, high-churn. Not worth offsite bytes. |

## 2. Why syncoid raw-send (not restic)

The data is already ZFS, already snapshotted, already encrypted at rest. That
makes `zfs send` the natural transport:

1. **Reuses the sanoid chain** — no separate "what state do I capture"
   scheduler. A snapshot is an atomic point-in-time of the whole dataset
   (photos *and* the ≤24h pg_dump captured together, consistently).
2. **`--raw` (`-w`) = encrypted end-to-end with zero key exposure.** We ship
   the *already-encrypted* ZFS blocks. The offsite box stores ciphertext and
   cannot read the photos even with physical access — it never has `tank`'s
   key. No second backup passphrase to manage.
3. **Block-level incrementals** — after the first seed, each run ships only the
   blocks changed since the last one, however long ago that was.
4. **Same tool family as sanoid** — `syncoid` ships with the `sanoid` package
   already in use. Restore is a bit-identical `zfs receive` of the full
   history.

restic would only win if there were no ZFS-capable remote (cheap dumb object
storage like B2/Storj) or we wanted a format-independent copy. We're choosing
the owned-hardware ZFS target, so raw-send is strictly better here.

## 3. The offsite host

A small **intermittently-connected** NixOS box at a **second physical location**
(friend/family), reached over the existing tailnet. It is **not always on** —
the plan is to power it up **roughly once a month**, let it sync automatically
on connect, then shut it back down. This is deliberate: less power draw, less
attack surface, and a naturally air-gapped copy #3 for most of the month.

- **Proposed name: `niflheim`** (realm of cold mist — apt for cold offsite
  storage). Final name TBD.
- **Hardware:** anything that holds a disk ≥ the immich library with headroom —
  mini-PC, RPi5 + USB SSD, or a retired machine. A single disk is acceptable
  (this is copy #3, not primary); a 2-disk mirror is nicer but optional.
  Intermittent duty makes a low-power mini-PC ideal.
- **Pool:** one ZFS pool (e.g. `cold`). It does **not** need its own native
  encryption — raw-received datasets arrive already encrypted under draupnir's
  key and stay that way at rest. The pool just needs to be a valid receive
  target.
- **Tailnet:** enrol via `hosts/optional/tailscale.nix` (gets a `100.64.0.x`).
  It is **not** on the home LAN, so `accept-routes` is a non-issue here (see
  the accept-routes LAN trap note) — but it *does* need to reach
  `ntfy.lan.valgrindr.net` for alerts, which resolves via AdGuard + bifrost's
  subnet route over tailscale. Confirm during bring-up.
- **Repo:** added like any host (`hosts/niflheim/`, `nixosConfigurations`
  entry, home config). See the "Adding a New Host" checklist in the root
  CLAUDE.md.

## 4. Replication topology: **pull, run-on-connect** (backup box initiates)

Two directions are possible; we choose **pull** for ransomware/compromise
resilience:

- **Pull (chosen):** `niflheim` initiates the `syncoid` job and reaches *into*
  draupnir with a **send-only** delegated user. A compromise of draupnir
  cannot reach out and destroy the offsite copies — draupnir has no
  credentials on niflheim and no way to delete what's already replicated.
  niflheim owns retention on its own copies.
- **Push (rejected):** simpler, but a compromised draupnir could delete the
  remote snapshots if it held destroy delegation. Weaker.

Because niflheim is **intermittent** (§3), the trigger is **run-on-connect, not
a nightly timer** — there's no point scheduling a 02:00 run on a box that's off
28 nights out of 30. It fires when the box powers up and can reach draupnir.

### Mechanics

- On draupnir: a **dedicated unprivileged user** (e.g. `syncoid`) with ZFS
  **`send,snapshot,bookmark,mount`** delegated on `tank/immich` and
  `tank/backups` (`zfs allow`), and an authorized SSH key. **No `destroy`, no
  `receive`, no `hold`.**
  The incremental base is preserved as a **bookmark**, not a hold — this is the
  deliberate choice for an intermittent target. A hold pins the base snapshot
  *and its data blocks* on draupnir for the entire absence, so a forgotten
  niflheim would bloat the **primary** pool (worst failure mode: you miss a
  backup *and* fill up the pool you're protecting). A bookmark is a **zero-space
  marker** of the base position that survives after sanoid prunes the snapshot,
  so draupnir stays exactly at its retention no matter how long niflheim is
  away. Each successful pull advances the `syncoid` bookmark on the latest sent
  snapshot, and the **age of that bookmark** is the liveness signal draupnir's
  watchdog reads (§6). (Raw incremental from a bookmark needs OpenZFS ≥ 2.1 —
  draupnir is fine; confirm at bring-up.)
- On niflheim: a **wrapper service triggered on boot + network-online**, ordered
  `After` tailscaled so the tailnet route to draupnir exists. It is **not** a
  clock timer — the trigger is connect, not schedule (§4 intro). The service
  runs the full workflow as one script and **retries on failure with backoff**
  (`Restart=on-failure`, `RestartSec` ≈ 5 min) — a transient (draupnir asleep,
  network still settling) just loops until it goes through. The workflow, in
  order:
  1. `syncoid --no-sync-snap --sendoptions=w syncoid@draupnir:tank/immich  cold/immich`
  2. `syncoid --no-sync-snap --sendoptions=w syncoid@draupnir:tank/backups cold/backups`
  3. `sanoid --prune-snapshots` over `cold/*` (bound the received history).
  4. **success ntfy** ("sync OK, snapshot X, N GB").
  5. **`poweroff`** — the box shuts itself down once copy #3 is current, so the
     "plug in, walk away" flow is fully hands-off.

  `--no-sync-snap` reuses sanoid's snapshots instead of creating throwaway
  ones; `--sendoptions=w` is the raw (encrypted) send. A monthly gap just means
  one larger incremental — block-level, so still only the changed blocks, not a
  re-seed. Because steps 4–5 only run on success, a **persistently failing**
  box never powers off: it keeps retrying, stays on, and emits the "still
  failing" ntfy (§6) so you can fix it while you're there.
- **Retention offsite (decoupled from draupnir):** syncoid only ever *adds*
  snapshots to `cold/*` — it never propagates draupnir's deletions — so
  niflheim's own **sanoid prune** (run inside the on-connect workflow, not a
  standalone timer that would rarely fire on an off-most-of-the-month box) is
  what bounds the copy. Received datasets are readonly, but that only blocks
  *data* writes; niflheim's root can still `zfs destroy` old snapshots. Because
  the sets are decoupled, niflheim keeps a **deeper** history than home:

  | Tier | draupnir (`irreplaceable`) | niflheim (`cold/*`) |
  |---|---|---|
  | hourly | 24 | 0 (no offsite value) |
  | daily | 30 | 30 |
  | monthly | 12 | 24 (2 yr) |
  | yearly | **3** (new — see below) | **10** |

  This needs a **new yearly tier on draupnir** (`irreplaceable` template gains
  `yearly = 3`), so true yearly snapshots are *created at the source* and flow
  over — niflheim's prune can only keep snapshot *types draupnir makes*, it
  can't mint a "yearly" from a monthly. niflheim then holds 10 yearlies even
  though draupnir keeps 3, the same way it holds 24 monthlies vs draupnir's 12:
  it received each while alive on the source and never deletes it.

  **How this behaves across a monthly gap (GFS).** Each connect ships whatever
  snapshots still exist on draupnir in the incremental window. With a ~monthly
  cadence the mid-gap hourlies/dailies are already pruned on draupnir before
  niflheim sees them, so **daily granularity offsite only covers the ~30 days
  around each connect**; the **monthly and yearly tiers are the load-bearing
  offsite history** — they live long enough on draupnir (12 mo / 3 yr) that a
  monthly connect always catches each one before it's pruned. So old periods
  restore to "the 1st of that month / that year," not to an arbitrary day.
  Standard grandfather-father-son thinning.

## 5. Secrets (sops)

- SSH private key on **niflheim** for `syncoid@draupnir` → `hosts/niflheim/secrets.yaml`.
- `syncoid@draupnir` authorized public key committed / declared on draupnir.
- ntfy token for niflheim's alert pushes (reuse the pattern of
  `zed-ntfy-token`; new topic, e.g. `backup-niflheim` or reuse `zfs-draupnir`).
- **No dataset-encryption key anywhere offsite** — that's the raw-send payoff.
  draupnir remains the only holder of `tank`'s key (hex keyfile at
  `/persist/tank.key`; keyformat=hex per `disko-data.nix`).

### Key recovery is part of the backup (the encrypted-backup trap)

An encrypted offsite copy is only as good as your ability to load the key
**after the same disaster** it defends against. niflheim stores pure ciphertext
and can never read it; recovery *requires* `tank`'s key. Today the key exists
in three places: `/persist/tank.key` on draupnir, sops
(`hosts/draupnir/secrets.yaml` → `tank-encryption-key`), and midgard
`~/backups/draupnir-install/persist/tank.key`. Two of those are **at home** —
the fire/theft event that justifies niflheim takes draupnir *and* midgard with
it. The survivor is then sops-in-the-repo (on GitHub), which is only decryptable
by an age recipient: draupnir's host key (gone with the box) or **your user age
key (`~/.ssh/id_ed25519`)**. So:

> The offsite ciphertext is recoverable **iff** `~/.ssh/id_ed25519` (or a direct
> copy of `tank.key`) survives independently of the house.

Action: keep a copy of the key — or the age key that unlocks sops — **off-site
and offline** (password manager that syncs to cloud, paper in another location,
and/or the YubiKey once [[project_yubikey_plan_pending]] lands). This is a
first-class deliverable of this plan, not an afterthought.

### Rotate `tank`'s key *before* the first seed

The `tank` wrapping key can be rotated any time with `zfs change-key` — it
re-wraps the fixed master key, rewrites **no data**, and loses nothing, even
mid-use. But `change-key` + raw send is the historically sharp corner of ZFS
encryption. Rotating **before** niflheim's first seed means niflheim is born
knowing exactly one key and that interaction never occurs. If you ever rotate
*after* seeding: no data-loss risk (master key is constant), but follow it with
a fresh **full raw re-seed on LAN** to re-establish niflheim's key-state
cleanly, or explicitly test `load-key` on a sent-back snapshot. Per the
rotation memo the tank key was *not* among the session-exposed creds, so this is
precautionary — but it's a 5-second command (`sudo zfs change-key tank`, new hex
key → update `/persist/tank.key` + sops + midgard backup), so do it now while
it's free.

## 6. Monitoring — split by who can observe what (reuse the ntfy bus)

The ZED→ntfy pipeline already exists (`hosts/draupnir/default.nix`:
`ZED_NTFY_URL = https://ntfy.lan.valgrindr.net`, topic `zfs-draupnir`). An
intermittent box forces the monitoring to split across **two** hosts, because
each alert must live where it can actually be observed:

- **niflheim → "I ran" (success).** On completion the workflow pushes ntfy
  ("sync OK, latest snapshot X, N GB moved") right before it powers off (§4).
- **niflheim → "still failing" (on, but can't succeed).** A box that's powered
  on and retrying but never succeeding — draupnir down, SSH key broken, pool not
  imported — never sends the success ping *and* never advances the bookmark, so the
  overdue watchdog is still ~45 days away. To catch this *while you're standing
  next to the box*, the workflow emits a "still failing after ~1h of retries"
  ntfy. (It stays on and keeps retrying — no poweroff without success.)
- **draupnir → "you're overdue" (the watchdog).** This is the piece that
  **cannot** live on niflheim: a box that is powered off can't emit a heartbeat
  telling you it's been too long. Since niflheim is off most of the month,
  *absence of a success ping is the normal state* and can't itself be the
  alarm. draupnir is the only always-on party that can notice the absence, so a
  small timer there checks **the age of the newest `syncoid` bookmark on
  `tank/immich`** (`zfs list -t bookmark -o name,creation`) and pushes ntfy if
  it exceeds a threshold (e.g. **> 45 days**): *"offsite copy is stale — connect
  niflheim."* The bookmark is a free, zero-space artifact of each successful
  pull (§4), so no niflheim→draupnir write channel or extra state is needed.

In short: **niflheim owns "I ran" / "I'm on but stuck"; draupnir owns "you
haven't run in too long."** The first two need niflheim powered on to fire; the
third is exactly the case niflheim can't cover, so it lives on the always-on
node. Together they close the classic silent-backup-failure gap — the same role
`ZED_NOTIFY_VERBOSE` plays by making scrub_finish double as a liveness proof,
but adapted to a node that's usually dark.

## 7. First seed — do it at home, then relocate

The initial full send is the whole library (hundreds of GB). **Bring niflheim
up on the home LAN first**, run the initial `syncoid` over gigabit, *then*
physically move the box to the offsite location. Every subsequent run is a tiny
incremental over the WAN. This avoids a multi-day WAN seed and any provider
seed-drive dance.

## 8. Restore drill (to be captured in a runbook)

Full-dataset recovery is the reverse send:
```
# on a rebuilt draupnir (tank imported, key loaded):
syncoid --sendoptions=w niflheim:cold/immich tank/immich
```
Because the stream is raw, the restored dataset is encrypted under `tank`'s
key — you must `zfs load-key` it, which only draupnir (key holder) can. The
offsite box never could.

**Single-file recovery does *not* work by browsing niflheim.** niflheim has no
key, so `cold/immich` there is opaque ciphertext — it cannot be mounted or have
a `.zfs/snapshot/` browsed. To pull one photo, **send that snapshot back to a
key-holder** (draupnir, or any box you load the key on) and browse it there.
Zero key exposure offsite is exactly why there's zero readability offsite —
that's the trade, not a bug.

## 9. Open decisions / risks

- **Hostname** for the offsite box (`niflheim` proposed).
- **Hardware + host site** — what box, whose house.
- **niflheim → ntfy reachability** over tailscale — verify the AdGuard rewrite
  + bifrost subnet route resolve `ntfy.lan.valgrindr.net` from a remote node
  (should, given `--accept-routes`; confirm).
- **`tank/backups` has no snapshots to send.** syncoid `--no-sync-snap` can only
  ship existing snapshots, but sanoid snapshots `tank/immich` only — so the
  backups leg (§1 table) is inert as designed. Fix before that leg goes live:
  give `tank/backups` a *light* sanoid policy (keeps `--no-sync-snap` + the
  no-`destroy` delegation). See `hosts/draupnir/CLAUDE.md` → "Adding a new
  dataset to the offsite replica".
- **Second offsite later?** One remote box is copy #3; a cloud restic tier
  (B2/Storj) could be added as copy #4 without touching this. Deferred.
- **niflheim uptime is by design** — the box is off most of the month (§3), so
  long gaps are the *expected* mode, not a fault. Incrementals just catch up
  (block-level) on next connect. The draupnir-side staleness watchdog (§6)
  surfaces a gap that grows *abnormally* long (forgot to plug it in, box dead).
- **Watchdog threshold tuning** — 45 days is a starting point for a ~monthly
  cadence (roughly "you've missed a cycle and a half"). Tighten/loosen after
  observing real connect frequency.
- **Worst case: niflheim gone longer than draupnir's longest tier (3 yr).**
  Nearly unreachable given the 45-day watchdog, but the consequences, worst to
  mild: (1) the incremental chain *may* need a **full re-seed** if the bookmark
  was removed or `tank` was rebuilt in the interim — annoying (do it on LAN),
  **not lossy** (master key is constant; niflheim's prior copies stay valid and
  independent). (2) A **point-in-time hole** for the blackout window: periods
  draupnir fully pruned and niflheim never caught have no fine-grained restore
  point — the only genuine loss, and near-moot for an append-mostly photo
  archive (live files still replicate; only something *created and deleted
  entirely within* the blackout is unrecoverable). (3) The copy is simply stale
  for the gap. Mitigation if a long absence is *planned*: bump draupnir's yearly
  retention beforehand so anchors/history span it.

## 10. Implementation phases

0. **Prep on draupnir (no niflheim needed yet).**
   - Add `yearly = 3` to the `irreplaceable` sanoid template (`services/
     sanoid.nix`) so yearlies start accruing before the seed.
   - Rotate `tank`'s key (`zfs change-key`, before any seed) and confirm an
     off-site/offline copy of the key exists (§5).
1. **Add `niflheim` to the repo** — host dir, OS on the **NVMe**
   (`btrfs-disk-uefi.nix`), the **whole HDD** as a single-disk **unencrypted**
   ZFS pool `cold` (host-local `disko-data.nix`, mirroring draupnir's), core +
   tailscale, `nixosConfigurations` entry, pre-generated host key + `&niflheim`
   in `.sops.yaml`. **Use DHCP, not a static LAN IP** — the box relocates, so it
   addresses via tailscale, not a fixed `192.168.1.x`. Install via
   nixos-anywhere on the home LAN (draupnir pattern).
2. **Delegate on draupnir** — `syncoid` user, `zfs allow
   send,snapshot,bookmark,mount` on `tank/{immich,backups}` (no `destroy`, no
   `hold`), authorized key. sops for the keypair.
3. **syncoid on niflheim** — pull of `tank/{immich,backups}` raw,
   `--no-sync-snap`, bookmark-based base, driven **run-on-connect** (boot +
   network-online after tailscaled, `Restart=on-failure` backoff); sanoid prune
   on `cold/*` (0h/30d/24m/10y) and **`poweroff` on success** in the same
   workflow.
4. **Seed on LAN**, then verify by **sending a `cold/immich` snapshot back to
   draupnir** and confirming it `load-key`s + mounts there (niflheim itself
   can't mount it — no key, §8).
5. **ntfy wiring (niflheim)** — success push + a "still failing after ~1h" push
   from the workflow.
6. **Staleness watchdog (draupnir)** — timer that alerts if the newest
   `syncoid` **bookmark** on `tank/immich` is older than 45 days.
7. **Relocate** niflheim offsite; confirm first WAN incremental + both alerts
   (a real run, and letting the watchdog window lapse once).
8. **Restore-drill doc** — `docs/immich-offsite-restore-runbook.md`.
