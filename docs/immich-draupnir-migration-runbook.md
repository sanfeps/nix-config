# Immich → draupnir cutover runbook

Moves Immich from asgard to draupnir. **This is a fresh install, not a data
migration**: the asgard instance ran in pre-NAS scaffold mode and was never
loaded with photos, so there is no DB dump, no file transfer, and no path
compatibility to preserve. The library sits directly on the raidz1 dataset at
its canonical mountpoint `/tank/immich`.

(An earlier revision of this runbook described a full pg_dump/tar migration
with a `/mnt/nas/immich` bind-mount path contract — see git history if a
with-data migration recipe is ever needed, e.g. for the later Jellyfin move,
which DOES carry state.)

Besides the move itself, this validates Caddy-on-draupnir (wildcard LE cert
via Njalla DNS-01) — the ingress building block the Jellyfin move reuses.

## Phase A — deploy draupnir

```bash
NIX_SSHOPTS="-i ~/.ssh/lykill" nixos-rebuild switch --flake .#draupnir \
  --target-host sanfe@192.168.1.56 --build-host sanfe@192.168.1.56 \
  --ask-sudo-password
```

Validate on draupnir:
- `systemctl status caddy immich-server immich-machine-learning postgresql`
- Wildcard cert issued (DNS-01 takes ~1 min): `journalctl -u caddy | grep -i obtain`
- `ls -ld /tank/immich` → owned `immich:immich` (upstream tmpfiles rule)
- From a client, bypassing DNS (which still points at asgard):
  `curl -sI --resolve immich.lan.valgrindr.net:443:192.168.1.56 https://immich.lan.valgrindr.net` → HTTP 200

## Phase B — flip DNS + decommission asgard (one commit)

1. `hosts/bifrost/services/dns.nix`: add a `draupnirIp = "192.168.1.56";`
   constant, point the `immich.${lanZone}` rewrite at it.
2. `hosts/asgard/services/immich.nix`: delete the file and its import in
   `hosts/asgard/services/default.nix`.
3. Update docs in the same commit: asgard CLAUDE.md (drop the immich entry),
   root CLAUDE.md (rewrites blurb mentions immich → asgard), and the homepage
   tile group on bifrost if it names asgard.
4. Deploy bifrost, then asgard. If a workstation still resolves `.54`:
   `resolvectl flush-caches`.
5. Register the admin account at `https://immich.lan.valgrindr.net`, log the
   phone app in (same URL as before — it's a new server, so it's a fresh
   login, not a reconnect).

Asgard leftovers to clean whenever (nothing valuable in them):
`sudo -u postgres dropdb immich`, `rm -rf /mnt/nas/immich /var/lib/immich`,
and the `/persist` mirror of `/var/lib/immich` if present.

## After the move

- Photos will land on redundant storage, but **offsite backup for tank/immich
  is still pending** (two-drive failure loses everything — flagged in the disk
  failure runbook). Sanoid snapshots on `tank/immich` are the planned next
  guard (draupnir plan Phase 5).
- RAM: ARC capped at 3 GiB (`hosts/draupnir/default.nix`). If ML jobs cause
  memory pressure, set `homelab.services.immich.machineLearning = false`.
