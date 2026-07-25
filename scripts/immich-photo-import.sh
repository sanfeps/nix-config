#!/usr/bin/env bash
set -euo pipefail

# immich-photo-import.sh — safely bulk-import photos/videos from an external
# drive into the Immich library on draupnir, using the official Immich CLI.
#
# DESIGN / WHY NOT `find | cp`:
#   /tank/immich is Immich's *managed* library, not a plain photo folder.
#   Immich tracks every asset in Postgres and lays them out via its storage
#   template ({{y}}/{{MM}}/{{filename}}). Copying files into that directory
#   directly makes Immich blind to them. The CLI is the correct ingress:
#     - reads the source READ-ONLY (it has no delete path unless you ask), so
#       your original drive is never modified;
#     - skips every non-media file automatically (knows all photo/video exts);
#     - recurses through nested folders;
#     - deduplicates by content hash — the same image under a different name,
#       folder, or drive is uploaded once and the rest are skipped, across runs;
#     - files everything by date so a messy source lands ordered in Immich.
#   Near-duplicates (re-encoded, not byte-identical) are caught afterwards by
#   Immich's duplicate-detection job (enabled in the draupnir config) for you
#   to review in the app.
#
# SAFETY: this script NEVER passes --delete or --delete-duplicates. It also
#   refuses to run against a source that is not mounted read-only, unless you
#   pass --allow-rw (belt-and-suspenders — the CLI still won't delete).
#
# Run this ON draupnir, with the drive plugged in via USB and mounted read-only.

# --- defaults -----------------------------------------------------------------
IMMICH_SERVER="${IMMICH_SERVER:-http://127.0.0.1:2283/api}"  # localhost = no TLS/cert hop
concurrency="${CONCURRENCY:-4}"   # gentle on the 8 GiB Pentium box + USB read
album=""                          # -A "name": put this batch in one album
album_per_folder=0                # -a: one album per source subfolder
dry_run=0
allow_rw=0
sources=()

# Optional ntfy completion ping (opt-in, best-effort — never fails the import).
# Off unless NTFY_TOPIC is set. Point it at whatever topic/token you want; the
# script hardcodes no secret. Grab a token from sops if the topic needs auth.
ntfy_url="${NTFY_URL:-https://ntfy.lan.valgrindr.net}"
ntfy_topic="${NTFY_TOPIC:-}"        # e.g. immich-import (or reuse zfs-draupnir)
ntfy_token="${NTFY_TOKEN:-}"        # bearer token; empty = anonymous publish

usage() {
  cat <<'EOF'
Usage: immich-photo-import.sh [options] <source-dir> [<source-dir>...]

Bulk-import photos/videos from a mounted drive into Immich. Read-only on the
source; never deletes anything.

Options:
  -n, --dry-run           Show what would be uploaded; upload nothing.
  -A, --album <name>      Add every asset from this run to one named album
                          (handy to review/rollback a batch, e.g. the drive).
  -a, --album-per-folder  Create one album per source subfolder instead.
      --concurrency <n>   Parallel uploads (default 4). Higher = faster but
                          heavier on the NAS.
      --allow-rw          Permit a read-write source mount (default: refuse).
  -h, --help              This help.

Optional completion notification (opt-in, best-effort):
  Set NTFY_TOPIC to get a push when the run finishes (success or failure) --
  handy for multi-hour drives. Off by default; the import never depends on it.
    NTFY_TOPIC=immich-import \
    NTFY_TOKEN=<publish-token> \
      ./immich-photo-import.sh -A "Family" /mnt/import
  NTFY_URL defaults to https://ntfy.lan.valgrindr.net. A separate topic needs
  an ntfy ACL entry on bifrost; reusing zfs-draupnir works with no changes.

First-time setup (once):
  1. In the Immich web UI: Account Settings -> API Keys -> New API Key.
  2. Authenticate the CLI:
       nix run nixpkgs#immich-cli -- login http://127.0.0.1:2283/api <API_KEY>

Which user owns the import (IMPORTANT):
  Assets are owned by the account whose API key you logged in with, and are
  private to that user. Ownership can't be transferred later, only shared
  (via albums). So log in as the RIGHT person before importing:
    - Family/common photos: log in as your admin/main account, import, then
      make a shared album and share it with the family.
    - Someone else's private photos: log in with THEIR key instead
      (immich login ... <their-key>), or have them upload from their devices.
  Switch accounts by re-running `immich login` (it overwrites auth.yml), or
  keep them apart with `-d/--config-directory` / IMMICH_CONFIG_DIR pointing at
  a separate auth.yml per user. `immich server-info` shows who you are now.

Typical run, per drive:
  sudo mount -o ro /dev/sdX1 /mnt/import          # read-only mount
  ./immich-photo-import.sh -n /mnt/import         # dry-run first, eyeball it
  ./immich-photo-import.sh -A "drive-X" /mnt/import
  sudo umount /mnt/import                          # next drive; dedup is automatic
EOF
}

# --- arg parse ----------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--dry-run) dry_run=1; shift ;;
    -A|--album) album="${2:?--album needs a name}"; shift 2 ;;
    -a|--album-per-folder) album_per_folder=1; shift ;;
    --concurrency) concurrency="${2:?--concurrency needs a number}"; shift 2 ;;
    --allow-rw) allow_rw=1; shift ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "unknown option: $1" >&2; usage; exit 2 ;;
    *) sources+=("$1"); shift ;;
  esac
done

if [[ ${#sources[@]} -eq 0 ]]; then
  echo "error: no source directory given" >&2
  usage; exit 2
fi

# --- resolve the CLI ----------------------------------------------------------
if command -v immich >/dev/null 2>&1; then
  immich_cmd=(immich)
else
  echo "immich CLI not on PATH; falling back to 'nix run nixpkgs#immich-cli'." >&2
  immich_cmd=(nix run nixpkgs#immich-cli --)
fi

# --- safety: read-only source check ------------------------------------------
for src in "${sources[@]}"; do
  if [[ ! -d "$src" ]]; then
    echo "error: source is not a directory: $src" >&2
    exit 1
  fi
  # Is the filesystem backing $src mounted read-only?
  opts="$(findmnt -no OPTIONS --target "$src" 2>/dev/null || true)"
  if [[ ",$opts," != *",ro,"* ]]; then
    if [[ $allow_rw -eq 1 ]]; then
      echo "WARN: $src is not a read-only mount (--allow-rw given, continuing)." >&2
    else
      echo "error: $src is not mounted read-only (opts: ${opts:-unknown})." >&2
      echo "       Remount with 'mount -o ro ...' or pass --allow-rw to override." >&2
      echo "       (The CLI still won't delete — this is the extra guard.)" >&2
      exit 1
    fi
  fi
done

# --- build the upload command -------------------------------------------------
# NOTE: --delete / --delete-duplicates are intentionally NEVER added.
args=(upload --recursive --concurrency "$concurrency")
[[ $dry_run -eq 1 ]]          && args+=(--dry-run)
[[ -n "$album" ]]             && args+=(--album-name "$album")
[[ $album_per_folder -eq 1 ]] && args+=(--album)
args+=("${sources[@]}")

# Auth (server URL + API key) comes from `immich login`, stored in
# ~/.config/immich/auth.yml. We don't set IMMICH_INSTANCE_URL/-u here so we
# can't silently disagree with what you logged in as.
if [[ ! -f "${IMMICH_CONFIG_DIR:-$HOME/.config/immich}/auth.yml" ]]; then
  echo "error: not logged in. Run first:" >&2
  echo "  ${immich_cmd[*]} login $IMMICH_SERVER <API_KEY>" >&2
  exit 1
fi

# Best-effort ntfy push. Never lets a notification problem affect the import.
notify() {
  [[ -n "$ntfy_topic" ]] || return 0
  command -v curl >/dev/null 2>&1 || { echo "notify: curl missing, skipping." >&2; return 0; }
  local title="$1" body="$2" prio="$3" tags="$4"
  local auth=()
  [[ -n "$ntfy_token" ]] && auth=(-H "Authorization: Bearer $ntfy_token")
  curl -fsS --max-time 15 "${auth[@]}" \
    -H "Title: $title" -H "Priority: $prio" -H "Tags: $tags" \
    -d "$body" "$ntfy_url/$ntfy_topic" >/dev/null \
    || echo "notify: push to $ntfy_url/$ntfy_topic failed (ignored)." >&2
}

echo "==> Immich import"
echo "    sources:     ${sources[*]}"
echo "    concurrency: $concurrency"
echo "    dry-run:     $([[ $dry_run -eq 1 ]] && echo yes || echo no)"
[[ -n "$album" ]] && echo "    album:       $album"
[[ -n "$ntfy_topic" ]] && echo "    notify:      $ntfy_url/$ntfy_topic"
echo

# Run the import (not exec'd, so we can ping afterwards) and keep its exit code.
set +e
"${immich_cmd[@]}" "${args[@]}"
rc=$?
set -e

# Dry-runs don't warrant a push; a real run pings on both success and failure.
if [[ $dry_run -eq 0 ]]; then
  label="${album:-${sources[*]}}"
  if [[ $rc -eq 0 ]]; then
    notify "Immich import done" "Finished: $label" "default" "white_check_mark,camera"
  else
    notify "Immich import FAILED" "Exit $rc: $label" "high" "warning,camera"
  fi
fi

exit "$rc"
