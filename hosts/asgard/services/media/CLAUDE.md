# media

Declarative media stack on asgard. Everything is native NixOS — no docker-compose, no Gluetun container. The acquisition plane (qbittorrent + the indexer/automation *arrs) runs inside a Mullvad WireGuard network namespace via [VPN-Confinement](https://github.com/Maroka-chan/VPN-Confinement); the playback / request plane (Jellyfin, Seerr) and the TRaSH sync (Recyclarr) sit outside the namespace on the host's normal network.

Scaffold mode is the rule: the `./media` import in `hosts/asgard/services/default.nix` stays **commented** until the manual bootstrap below is done. Same pattern as `services/immich.nix`. The module files themselves can land in `main` independently.

## Topology at a glance

```
                                    bifrost (192.168.1.55)
                                    ├── Caddy *.lan.valgrindr.net (wildcard LE via Njalla DNS-01)
                                    ├── AdGuard rewrites → bifrost
                                    └── Homepage tiles
                                              │
                                              ▼  reverse_proxy 192.168.1.54:<port>
                                    ┌────────────────────────────────────┐
                                    │ asgard (192.168.1.54) — host net   │
                                    │                                    │
                                    │  Jellyfin :8096    Seerr :5055     │
                                    │  Recyclarr (timer, talks loopback) │
                                    │                                    │
                                    │  ┌────── Mullvad netns ──────────┐ │
                                    │  │ qBittorrent :8080             │ │
                                    │  │ Prowlarr    :9696             │ │
                                    │  │ Sonarr      :8989             │ │
                                    │  │ Radarr      :7878             │ │
                                    │  │  (egress only via WireGuard)  │ │
                                    │  └───────────────────────────────┘ │
                                    │           ▲ portMappings           │
                                    │           │ (host loopback ↔ ns)   │
                                    └────────────────────────────────────┘
```

`accessibleFrom` on the namespace whitelists the LAN, tailnet, and host loopback so port mappings are reachable from all three.

## Why the split?

Two egress requirements, irreconcilable on a single uplink:

- **Acquisition plane** (qbittorrent, prowlarr, sonarr, radarr) — must egress through Mullvad. RSS pulls, indexer scrapes, torrent peers all flow over WireGuard.
- **Playback / request plane** (Jellyfin, Seerr) — must egress through the LAN. Jellyfin needs LAN-visible DLNA + transcoding, Seerr fetches TMDb metadata.

Network namespaces let both coexist on the same host without dual-routing tricks. The *arrs that talk to qBittorrent (sonarr, radarr) live in the same namespace, so the download client URL is `http://127.0.0.1:8080` even though that's the namespace's loopback.

Recyclarr sits **outside** the namespace because (a) it only talks to localhost APIs (via port mappings) and to api.github.com (clear, public), and (b) running it confined would force tunnel egress for a low-stakes scheduled task with zero privacy upside.

## File map

- `default.nix` — imports list: vpn, storage, qbittorrent, prowlarr, sonarr, radarr, jellyfin, seerr, recyclarr, bootstrap.
- `vpn.nix` — `vpnNamespaces.mullvad`. Reads `sops.secrets."media/mullvad-wg-conf"`. **Sole** writer of the namespace; per-service modules only append `portMappings`.
- `storage.nix` — `/srv/media{,/downloads}` (tmpfiles), `users.groups.media`. NFS automount for `/mnt/nas/media/library` is commented until the NAS lands. Downloads stay **ephemeral on /srv** — see "Storage decisions" below.
- `qbittorrent.nix` — native `services.qbittorrent` with `serverConfig` declaring WebUI + paths. In the netns.
- `prowlarr.nix` — uses the module's `dataDir` override (`/srv/media/state/prowlarr`) as the **only sane persistence path**. See "DynamicUser persistence trap" below.
- `sonarr.nix` / `radarr.nix` — default `dataDir`; persist `/var/lib/{sonarr,radarr}` (static users, no trap). In the netns.
- `jellyfin.nix` — outside the netns. Library will point at `/mnt/nas/media/library`; until the NAS lands, comes up empty.
- `seerr.nix` — outside the netns. Uses `DynamicUser = true` + `StateDirectory = "jellyseerr"` (bind-mount `/var/lib/private/jellyseerr` → `/var/lib/jellyseerr`). Since asgard's rootfs is **not** wiped on boot, this state persists naturally — no `environment.persistence` declaration needed. See header comment in `seerr.nix`.
- `recyclarr.nix` — outside the netns. Pre-service oneshot stages API keys from each *arr's `config.xml`.
- `bootstrap.nix` — boot-time reconciler (Python oneshot, root, runs inside the mullvad netns so loopback DNAT works). Idempotently registers Sonarr/Radarr in Prowlarr, configures qBittorrent as the download client on both *arrs, declares root folders (`/mnt/nas/media/library/{tv,movies}`, backed by storage.nix tmpfiles dirs pre-NAS), applies the local-address auth bypass, and (once the Seerr wizard has run) registers Sonarr/Radarr inside Seerr. See "Inter-service wiring" below for the data flow.

## Storage decisions

- **`/srv/media/downloads`** (ephemeral, on /persist via /srv being a regular subvolume): qBittorrent's `DefaultSavePath`. Sonarr/Radarr `Move` (not `Hardlink`) imports from here to the library on the NAS, then delete the source. We're a Mullvad leecher (no port forwarding), so seeding is impossible — there's nothing to preserve cross-host or cross-reboot. **No NAS round-trip for downloads.**
- **`/mnt/nas/media/library`** (NAS-mounted, NFS): final media library, mounted read-write for the *arrs to write into, read-only for Jellyfin (group `media`). Until the NAS lands, `storage.nix` backs this path with local tmpfiles dirs (`library/{tv,movies}`, group `media`, mode 0775) so the full workflow can be validated end-to-end on local disk. When the NAS lands, uncomment the `fileSystems."/mnt/nas/media"` block and drop the `TEMP(no-nas)` tmpfiles lines — NFS overlays the same path, so nothing else in the stack changes.
- **`/srv/media/state/prowlarr`** — only because the upstream `prowlarr` module uses `DynamicUser` (see below).
- **`/var/lib/<service>`** for static-user services: persisted via `environment.persistence."${config.hostSpec.persistFolder}".directories`.

## DynamicUser + persistence (asgard caveat)

Three modules in this stack use `DynamicUser = true`. On **midgard** (wipe-on-boot rootfs from `btrfs-luks-impermanence-disk.nix`) this combination is genuinely tricky: `StateDirectory` creates `/var/lib/private/<svc>` and bind-mounts it to `/var/lib/<svc>` on every boot, but a fresh boot wipes the underlying subvolume, and naïvely declaring `environment.persistence."/persist".directories = ["/var/lib/<svc>"]` races with systemd's first-boot migration logic. On asgard (this host) the rootfs is **not** wiped (`btrfs-disk-uefi.nix`, no `postDeviceCommands`), so `/var/lib/private/<svc>` just sits there persistently and the trap is moot. The three modules and how we treat them here:

- `services.prowlarr` — module **does** expose `dataDir`. We override to `/srv/media/state/prowlarr` for two reasons: (a) it's the only sane way to extract the API key reliably (`/var/lib/private/<dynamic-uid>/...` is harder to reason about), and (b) it co-locates Prowlarr state with the other media state under `/srv/media`. ✅ Persistence works.
- `services.seerr` — module **does not** expose `dataDir`. Overriding `configDir` breaks startup (nixpkgs issue #457739). We accept the `/var/lib/private/jellyseerr` location as-is; on asgard it persists naturally. **No `environment.persistence` declaration**, no migration race. The reconciler reads `settings.json` from `/var/lib/private/jellyseerr/settings.json` (root can traverse it).
- AdGuard on bifrost has the same shape; same reasoning — bifrost's rootfs is also non-wipe, so the "leave it ephemeral" note in the root CLAUDE.md is overly cautious for that host.

The other modules (`qbittorrent`, `sonarr`, `radarr`, `jellyfin`, `recyclarr`) use **static** users; `environment.persistence` is also unnecessary on asgard for the same rootfs-isn't-wiped reason, but the explicit declarations remain in place as documentation of intent and to keep the modules portable to wipe-on-boot hosts.

**If/when any of these services moves to a wipe-on-boot host (midgard or future), revisit this section** — the trap is real on those layouts.

## Bootstrap (one-time, manual)

The stack is fully declarative, but two things need a manual seed before the import comes off the commented list:

### 1. Mullvad WireGuard config

```bash
# Local: log into mullvad.net → WireGuard configuration generator,
# generate a key, pick ONE server, download the .conf.
# Edit it to confirm `DNS = 10.64.0.1` is under [Interface] (leak belt).
sops hosts/asgard/secrets.yaml   # add key: media/mullvad-wg-conf, value: full conf as multiline YAML
```

### 2. Jellyfin admin creds (for Seerr wizard automation)

Jellyfin's first-run wizard is left manual on purpose — its `/Startup/...` API
shape changes between releases and isn't worth chasing. Walk through it once in
the Jellyfin UI (create an admin user, point libraries at
`/mnt/nas/media/library/{tv,movies}`). State persists naturally.

Then seed the same creds in sops so the boot-time reconciler can drive Seerr's
own first-run wizard via `/api/v1/auth/jellyfin`:

```bash
sops hosts/asgard/secrets.yaml
# add:
#   media/jellyfin-admin-username: <jellyfin admin user>
#   media/jellyfin-admin-password: <jellyfin admin password>
```

Skip this if you don't mind clicking through Seerr's wizard manually too — the
reconciler logs the missing creds and moves on. Once the wizard has run once
(by any path), the *arr registration inside Seerr is fully reconciled on every
boot.

### 3. NAS mount (skip until NAS is provisioned)

Once the NAS exists at `nas.lan` (or wherever) exporting an NFS share:
1. Uncomment the `fileSystems."/mnt/nas/media"` block in `storage.nix`.
2. Verify mount comes up: `systemctl status mnt-nas-media.automount`.
3. Sonarr/Radarr root folders are already pointing at `/mnt/nas/media/library/{tv,movies}` (declared by the reconciler). Jellyfin's library paths still need pointing in the UI on first-run (not automated — see Bootstrap §2).

### 4. Activate the import

Uncomment `./media` in `hosts/asgard/services/default.nix` and deploy. The Mullvad namespace comes up immediately at activation; per-service WebUIs become reachable through the bifrost Caddy handles as soon as each unit starts.

## Bifrost wiring

Everything in this stack is Pattern-B (per the root CLAUDE.md): the service listens directly on asgard, asgard's firewall locks the port to `192.168.1.55` (bifrost), and bifrost terminates TLS. The bifrost-side wiring is:

- `hosts/bifrost/services/media-proxies.nix` — six Caddy handles (jellyfin/seerr/qbittorrent/prowlarr/sonarr/radarr) → `192.168.1.54:<port>`.
- `hosts/bifrost/services/dns.nix` — six AdGuard rewrites pointing each `*.lan.valgrindr.net` name at bifrost.
- `hosts/bifrost/services/homepage.nix` — "Media (asgard)" group with all six tiles.

Until `./media` is uncommented on asgard, the Caddy handles 502 cosmetically. That's expected scaffold-mode behaviour.

## Inter-service wiring

The *arrs talk to each other (Prowlarr syncs indexers to Sonarr/Radarr; Sonarr/Radarr push downloads to qBittorrent; Seerr forwards requests to Sonarr/Radarr). All those connections are **runtime** — they live in each service's SQLite DB, not in Nix.

We do **not** pre-seed API keys via sops: the *arrs generate them on first boot inside their `config.xml`. Two consumers read those keys back:

- **Recyclarr** — its own pre-service oneshot (`recyclarr-credentials.service`) extracts and stages keys under `/var/lib/recyclarr-credentials/`, then systemd's `LoadCredential=` feeds them to recyclarr.
- **`bootstrap.nix` reconciler** — `media-bootstrap.service`, a Python oneshot running as root **inside the mullvad netns** (so `127.0.0.1:<port>` reaches the confined *arrs; PREROUTING DNAT doesn't fire on host-local loopback). Extracts keys live from each `config.xml` (and Seerr's `settings.json`), then idempotently REST-configures:
  - **Prowlarr → Sonarr / Radarr** (`/api/v1/applications`) so indexers cascade automatically.
  - **Prowlarr public indexers** (`/api/v1/indexer/schema` → `/api/v1/indexer`) — auto-enables a curated allow-list of Cardigann definitions that don't need auth (currently just Internet Archive). New indexers cascade to Sonarr/Radarr via the Apps registration above. Private / API-key indexers are deliberately not declared — they belong in the Prowlarr UI so secrets don't end up in the reconciler.
  - **Sonarr → qBittorrent** (`/api/v3/downloadclient`) with category `tv-sonarr`.
  - **Radarr → qBittorrent** with category `movies-radarr`.
  - **Sonarr / Radarr root folders** (`/api/v3/rootfolder`) — declares `/mnt/nas/media/library/tv` and `/mnt/nas/media/library/movies` as the library targets. The dirs are pre-created by storage.nix as tmpfiles entries, so this works pre-NAS; once the NFS mount lands, the same paths are overlaid by the remote share with no *arr-side change.
  - **Auth bypass on the *arrs** (`/api/v{3,1}/config/host`) — sets `authenticationMethod=forms` + `authenticationRequired=disabledForLocalAddresses` and seeds an admin user (`admin` / password from sops `media/arr-admin-password`). LAN traffic via Caddy comes from 192.168.1.55 which is RFC1918, so the *arrs treat it as "local" and skip the form; off-LAN (tailnet) hits the form with the seeded creds. **qBittorrent** is handled separately and natively: its `AuthSubnetWhitelist` already covers LAN + tailnet + loopback (`qbittorrent.nix`), no reconciler step needed.
  - **Seerr first-run wizard** (`/api/v1/auth/jellyfin` → `/api/v1/settings/jellyfin` → `/api/v1/settings/initialize`) — if `media/jellyfin-admin-{username,password}` are set in sops, the host-side reconciler logs into Jellyfin via Seerr, creates the mirror admin user, persists the Jellyfin connection (including `externalHostname = https://jellyfin.lan.valgrindr.net` for UI deep-links), and flips `public.initialized`. Jellyfin's own first-run wizard is **not** automated — its `/Startup/...` API is version-fragile, so we leave that as a single manual step (see Bootstrap §2). Skip the sops seed and the reconciler logs + moves on; Seerr's wizard can be done manually instead.
  - **Seerr → Sonarr / Radarr** (`/api/v1/settings/sonarr` and `/api/v1/settings/radarr`) — runs after the wizard auto-run (or whenever `settings.json.initialized = true`). Reconciled via the bifrost edge URLs (`sonarr.lan.valgrindr.net:443` / `radarr.lan.valgrindr.net:443`) because Seerr lives on the host and PREROUTING DNAT to the netns only fires for incoming connections.

The reconciler is **best-effort**: any failed step is logged and skipped, the unit always exits 0. Inspect `journalctl -u media-bootstrap` after a deploy to see what landed.

Scoped out of the reconciler:
- **Private / auth-bearing indexers** — anything requiring API keys, logins, or cookies belongs in the Prowlarr UI so secrets don't leak into Nix-controlled state. The reconciler's `PUBLIC_INDEXERS` list only covers definitions that are free + open + cascade safely from a fresh install.
- **Quality profiles / custom formats** — owned by recyclarr.
- **Jellyfin first-run wizard** — Jellyfin's `/Startup/...` API shape changes between releases and isn't worth chasing. Click through it once in the Jellyfin UI (admin user + library paths), then seed the same creds in sops for the Seerr-side automation.

If the reconciler ever supersedes recyclarr's credential staging, the two credentials directories can be unified. For now, each owns its own — minor duplication is fine.

## VPN-Confinement port mapping pattern

Each service in the namespace appends to the shared `portMappings` list:

```nix
vpnNamespaces.mullvad.portMappings = [
  { from = <hostPort>; to = <nsPort>; protocol = "tcp"; }
];
```

`from` is what gets exposed on the host's network (the LAN IP and loopback per `accessibleFrom`); `to` is the port the confined process binds to inside the namespace. We use `from == to` everywhere for clarity. Two services in the same namespace can't bind the same `to` port (they share loopback), but using distinct upstream ports (8080, 8989, 7878, 9696) sidesteps that entirely.

## DNS leak belt

Mullvad's official conf includes `DNS = 10.64.0.1`. VPN-Confinement also routes NSCD socket lookups through the namespace, but only UDP DNS is well-tested. Keeping `DNS = 10.64.0.1` in the conf is belt-and-suspenders against accidental clear DNS resolution from inside the namespace. **Don't strip it during sops seeding.**

## Adding a new service to this stack

1. Drop a file in this folder, listing it in `default.nix`.
2. Decide: confined or unconfined? If confined, add `systemd.services.<name>.vpnConfinement = { enable = true; vpnNamespace = "mullvad"; }` and an entry to `vpnNamespaces.mullvad.portMappings`.
3. Pattern-B firewall: open the port to `192.168.1.55` only.
4. Add a Caddy handle in `hosts/bifrost/services/media-proxies.nix`.
5. Add an AdGuard rewrite in `hosts/bifrost/services/dns.nix`.
6. Add a Homepage tile in the "Media (asgard)" group in `hosts/bifrost/services/homepage.nix`.
7. Decide on persistence: static user → straight `environment.persistence`; DynamicUser → check for a `dataDir`-style escape hatch first. If none, accept ephemeral and add a TODO.
8. If it has an API key the reconciler needs, add an extractor to that pipeline.

## Recovery cheats

- **Service starts but the WebUI is unreachable from bifrost**: check the netns port mapping is published. `ip netns exec mullvad ss -ltnp` inside the namespace shows what's actually listening; `sudo iptables -t nat -L | grep <port>` shows the host-side DNAT.
- **Sonarr/Radarr can't reach qBittorrent**: confirm both are in the `mullvad` namespace (`systemctl show <svc> | grep NetworkNamespacePath`). The download client URL must be `http://127.0.0.1:8080` (namespace loopback), not the host IP.
- **Recyclarr fails with "401 Unauthorized"**: `recyclarr-credentials.service` ran but staged a stale or wrong key. `journalctl -u recyclarr-credentials` will show the extraction; verify the `<ApiKey>` element in `/var/lib/sonarr/config.xml` matches the running instance.
- **Bootstrap reconciler reports `POST … failed (401|403)`**: the *arr's API key extracted from `config.xml` doesn't match what the running instance expects (typically because the *arr restarted and rolled its key after `media-bootstrap.service` started but before it raced ahead). Run `systemctl restart media-bootstrap` manually; if it persists, check `<ApiKey>` ↔ running-state alignment via the *arr's UI.
- **Bootstrap reconciler reports `TIMEOUT waiting`**: a *arr exceeded the 180s readiness window. Either the service crashed (`systemctl status <svc>`) or boot-time DB migrations are running long; rerun `systemctl restart media-bootstrap` after the service settles.
- **Sonarr/Radarr show "qBittorrent: 401" in their download client tests**: qBittorrent's `AuthSubnetWhitelist` doesn't include `127.0.0.1/32`. Verify in `qbittorrent.nix` and that the WebUI conf was actually re-rendered (the module only re-writes `qBittorrent.conf` when changed).
- **`media/mullvad-wg-conf` decryption fails**: usual sops drift — `sops updatekeys hosts/asgard/secrets.yaml`. Until decryption succeeds, the namespace fails to come up and every confined service hangs in `activating (auto-restart)`.
- **Downloads piling up on /srv**: with `Move` semantics, the source should be deleted right after the *arr import. If they're not, the *arr's "Failed to import" log has the reason — usually a permissions issue on the NAS mount or a category mismatch with qBittorrent.
