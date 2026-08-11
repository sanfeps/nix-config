# media

Declarative media stack on asgard. Everything is native NixOS — no docker-compose, no Gluetun container. The acquisition plane (qbittorrent + the indexer/automation *arrs) runs inside a Mullvad WireGuard network namespace via [VPN-Confinement](https://github.com/Maroka-chan/VPN-Confinement); the request plane (Seerr) and the TRaSH sync (Recyclarr) sit outside the namespace on the host's normal network.

> **Jellyfin moved to draupnir 2026-07-26.** The playback server used to run here, but asgard is a QEMU VM with no usable GPU (virtual `card0`, no render node), so HEVC/DDP files forced CPU transcode and playback froze. It now lives on bare-metal draupnir (`hosts/draupnir/services/jellyfin.nix`) with Intel Quick Sync HW transcode, reading the library locally. **asgard still owns everything else** (acquisition + Seerr + yt2jelly), and still NFS-mounts the library so the *arrs and yt2jelly can write to it. Seerr and yt2jelly reach Jellyfin over the LAN via draupnir's Caddy edge (`https://jellyfin.lan.valgrindr.net`), not loopback. Mentions of "Jellyfin on 127.0.0.1:8096" below are historical.

Scaffold mode is the rule: the `./media` import in `hosts/asgard/services/default.nix` stays **commented** until the manual bootstrap below is done. The module files themselves can land in `main` independently.

## Topology at a glance

```
   bifrost (192.168.1.55)            client → https://<svc>.lan.valgrindr.net
   └── AdGuard: rewrites every             │ (AdGuard answers 192.168.1.54)
       media name → 192.168.1.54           ▼
                                  ┌────────────────────────────────────────┐
                                  │ asgard (192.168.1.54) — host net        │
                                  │  Caddy *.lan.valgrindr.net (own LE cert)│
                                  │   ├─ seerr    → 127.0.0.1:5055          │
                                  │   └─ qbit/prowlarr/sonarr/radarr        │
                                  │        → 192.168.15.1:<port> (veth)     │
                                  │  Recyclarr (timer, talks loopback)      │
                                  │                                         │
                                  │  ┌──── Mullvad netns (192.168.15.1) ──┐ │
                                  │  │ qBittorrent :8080  Prowlarr :9696  │ │
                                  │  │ Sonarr      :8989  Radarr   :7878  │ │
                                  │  │  (egress only via WireGuard)       │ │
                                  │  └────────────────────────────────────┘│
                                  │   mullvad-br 192.168.15.5/24 ◄─ Caddy   │
                                  └─────────────────────────────────────────┘
```

Per-host-caddy Phase 4: asgard's own Caddy fronts the five remaining WebUIs
(Jellyfin's vhost moved to draupnir with the service); bifrost is
not in the request path (AdGuard just points the names at asgard). The
confined four are reached at the namespace veth IP `192.168.15.1:<port>` over
the `mullvad-br` bridge, **not** loopback — the VPN-Confinement DNAT only
fires for incoming connections, so host-local Caddy bypasses it and hits the
veth directly (the `portMappings` entries provide the in-namespace INPUT
ACCEPT that permits this). `accessibleFrom` whitelists the LAN, tailnet, and
host loopback for the namespace's return path.

## Why the split?

Two egress requirements, irreconcilable on a single uplink:

- **Acquisition plane** (qbittorrent, prowlarr, sonarr, radarr) — must egress through Mullvad. RSS pulls, indexer scrapes, torrent peers all flow over WireGuard.
- **Request plane** (Seerr) — must egress through the LAN. Seerr fetches TMDb metadata and reaches Jellyfin-on-draupnir via the LAN Caddy edge. (Jellyfin itself moved to draupnir — same LAN-egress reasoning applied there.)

Network namespaces let both coexist on the same host without dual-routing tricks. The *arrs that talk to qBittorrent (sonarr, radarr) live in the same namespace, so the download client URL is `http://127.0.0.1:8080` even though that's the namespace's loopback.

Recyclarr sits **outside** the namespace because (a) it only talks to localhost APIs (via port mappings) and to api.github.com (clear, public), and (b) running it confined would force tunnel egress for a low-stakes scheduled task with zero privacy upside.

## File map

- `default.nix` — imports list: vpn, storage, qbittorrent, prowlarr, sonarr, radarr, music-dl, yt2jelly-ui, seerr, recyclarr, bootstrap, caddy. (jellyfin.nix removed 2026-07-26 — moved to draupnir.)
- `vpn.nix` — `vpnNamespaces.mullvad`. Reads `sops.secrets."media/mullvad-wg-conf"`. **Sole** writer of the namespace; per-service modules only append `portMappings`.
- `storage.nix` — anchors the `/mnt/nas` automount parent (tmpfiles), `users.groups.media` (**gid pinned 1500** — the cross-host contract with draupnir's NFS export; NFSv4 `sec=sys` maps numerically). Two NFSv4 **automounts** off draupnir: `/mnt/nas/media` ← `192.168.1.56:/tank/media` (arr library **+ `downloads/` staging**) and `/mnt/nas/essentials` ← `192.168.1.56:/tank/essentials` (the snapshotted keep-forever set). **Downloads now live on the NAS** (`/mnt/nas/media/downloads`), no longer on asgard's local `/srv` — see "Storage decisions" below. The `media`-group dirs are **setgid `2775`** (not `0775`): the shared-group design only works for *writes* if new subdirs inherit group `media` (setgid) and stay group-writable. Without it, a folder made by one media-group member (the yt2jelly daemon as `yt2jelly`, sonarr/radarr, or a manual `yt2jelly` CLI run as `sanfe`) lands under the creator's *primary* group with no group-write, and the next member hits `mv: Permission denied`. Pair with `umask 002` in the writers (music-dl.nix). The setgid dirs live on **draupnir** now (`hosts/draupnir/services/nfs.nix`); asgard just mounts them.
- `qbittorrent.nix` — native `services.qbittorrent` with `serverConfig` declaring WebUI + paths. In the netns.
- `prowlarr.nix` — default `dataDir` (`/var/lib/private/prowlarr` via DynamicUser `StateDirectory`). We deliberately **do not** override `dataDir`: the override's bind-mount + a `root:root 0700` tmpfiles rule on the bind source fight systemd's DynamicUser ownership and wedge the service with `EACCES` on its own data dir. See "DynamicUser + persistence trap" below.
- `sonarr.nix` / `radarr.nix` — default `dataDir`; persist `/var/lib/{sonarr,radarr}` (static users, no trap). In the netns.
- `flaresolverr.nix` — Cloudflare challenge solver for Prowlarr, **confined to the Mullvad netns** (it makes the real request to the indexer, so it must egress through the tunnel or it leaks the WAN IP). No vhost/DNS/portMapping — its only client is Prowlarr in the same netns (`http://127.0.0.1:8191`). Wire it in the Prowlarr UI: Settings → Indexers → Indexer Proxies → FlareSolverr, host `http://127.0.0.1:8191`, tag `cloudflare`, then tag the CF indexers. **DNS:** all confined units (the *arrs, qBittorrent, FlareSolverr) need the netns resolv.conf bind-mounted over `/etc/resolv.conf` — done centrally in `vpn.nix`. Without it they inherit the host's systemd-resolved stub (`127.0.0.53`), which is dead inside the namespace, so DNS fails ~100% (`Resource temporarily unavailable` for glibc, `ERR_NAME_NOT_RESOLVED` for Chromium). See the long comment in `vpn.nix`.
- `jellyfin.nix` — **moved to draupnir 2026-07-26** (`hosts/draupnir/services/jellyfin.nix`), where it reads the same library locally off `tank/media`/`tank/essentials` with Quick Sync HW transcode. No Jellyfin unit runs on asgard anymore. Seerr's connection to it + yt2jelly's refresh call now target the draupnir Caddy edge (`https://jellyfin.lan.valgrindr.net`), wired in `bootstrap.nix` / `music-dl.nix`.
- `music-dl.nix` — `yt2jelly`, a `writeShellApplication` (system package, not a service). One-shot yt-dlp pipeline that grabs a song into `/mnt/nas/media/library/music` under `$artist/Singles/$title`, then Jellyfin's own metadata providers enrich it. Tagging is free/best-effort: yt-dlp keeps YouTube's structured music metadata when present and a `--parse-metadata "title:%(artist)s - %(title)s"` rule recovers `artist` from "Artist - Title" titles (covers label-archive uploads where YouTube only gives the uploader). `ARTIST=`/`TITLE=`/`ALBUM=` env vars override. **Album tags drive Jellyfin grouping**: the script always writes `album` + `album_artist` (yt-dlp never sets `album_artist`, and a *blank* `album` makes Jellyfin guess an album by online name-match, mis-merging unrelated singles). Precedence: `ALBUM=` override → the album YouTube embedded (real music videos carry it) → fallback `"Singles"`; `album_artist` is always set to `artist` (keeps `feat.` tracks out of a Various-Artists bucket). A fast `ffmpeg -c copy` remux applies the tags (thumbnail preserved). Invoker must be in the `media` group, and the library tree must be setgid (see storage.nix above) or the `mv` into a sibling's folder fails. Outside the netns — a manual CLI, not part of the acquisition plane. **No acoustic recognition**: AcoustID/Chromaprint (beets) misses YouTube rips, Shazam-grade APIs (AudD/ACRCloud) are paid, and shazamio is unpackaged/broken in nixpkgs (needs `shazamio-core`) — see the git history of this file for that investigation. If a paid recognizer is ever wanted, add a recognize-step before the tag-write; the pipeline is structured for it. The same file also defines **`yt2jellyd`** — a small Python HTTP daemon (`writePython3Bin`, system user `yt2jelly` in group `media`) that wraps the CLI for phone use: binds `127.0.0.1:8398`, fronted by asgard's Caddy at `https://yt2jelly.lan.valgrindr.net`, bearer-token auth (token auto-generated at `/var/lib/yt2jellyd/token`), accepts only YouTube hosts. `POST /add {"url":…}` runs `yt2jelly` in a thread and then calls Jellyfin `/Library/Refresh` (auth via the `media/jellyfin-admin-*` sops creds, rendered into `yt2jellyd-env`); `GET /jobs` lists recent jobs; `GET /health` is unauthenticated. **Two gotchas:** (1) like any new service it needs an AdGuard rewrite in `hosts/bifrost/services/dns.nix` (`yt2jelly` → asgard) — without it the name doesn't resolve and curl fails silently; flush asgard's resolved cache (`resolvectl flush-caches`) after adding it since the negative answer gets cached. (2) The Jellyfin refresh uses Python `urllib` (no Happy-Eyeballs), so asgard needs the IPv4-first `networking.getaddrinfo.precedence` block in `hosts/asgard/default.nix` or the call hangs on the unreachable tailscale IPv6.
- `seerr.nix` — outside the netns. Uses `DynamicUser = true` + `StateDirectory = "jellyseerr"` (bind-mount `/var/lib/private/jellyseerr` → `/var/lib/jellyseerr`). Since asgard's rootfs is **not** wiped on boot, this state persists naturally — no `environment.persistence` declaration needed. See header comment in `seerr.nix`.
- `recyclarr.nix` — outside the netns. Pre-service oneshot stages API keys from each *arr's `config.xml`.
- `bootstrap.nix` — boot-time reconciler (Python oneshot, root, runs inside the mullvad netns so loopback DNAT works). Idempotently registers Sonarr/Radarr in Prowlarr, configures qBittorrent as the download client on both *arrs, declares root folders (`/mnt/nas/media/library/{series,movies}`, backed by draupnir's NFS-exported `tank/media`), applies the local-address auth bypass, and (once the Seerr wizard has run) registers Sonarr/Radarr inside Seerr. See "Inter-service wiring" below for the data flow.

## Storage decisions

- **`/mnt/nas/media/downloads`** (NFSv4, a **subdirectory** of draupnir's `tank/media` dataset — *not* a child dataset): qBittorrent's `DefaultSavePath`/`TempPath`. Moved off asgard's local `/srv/media/downloads` 2026-08-11 — two big concurrent downloads filled the 200 GB VM disk + the Proxmox thin-pool → 100% → `io-error` freeze (same class as the 2026-07-26 crash). Because downloads and `library/` are in the **same filesystem**, Sonarr/Radarr's `Move` import is an atomic server-side **rename** (faster than the old local→NFS copy), then the *arrs delete the staging copy (Mullvad leecher, no port-forwarding → nothing to seed). **Netns caveat:** qBittorrent runs in the Mullvad netns, but the NFS client transport is bound to the *mount's* netns (the host's), so download writes egress asgard→draupnir over the **LAN** while peer traffic stays tunneled — no leak. Trade-off accepted: the automount is `soft,timeo=30`, so a draupnir hiccup surfaces as a transient I/O error on the active download (recheck recovers).
- **`/mnt/nas/media/library`** (NFSv4 automount off draupnir `tank/media`): final media library — `library/{series,movies,music}`, read-write for the *arrs, read-only for Jellyfin (group `media`, gid 1500). The setgid `2775` tree lives on draupnir (`nfs.nix`); asgard just mounts it. **`tank/media` is NOT snapshotted** (churny + re-downloadable).
- **`/mnt/nas/essentials`** (NFSv4 automount off draupnir `tank/essentials`): curated keep-forever films, **snapshotted** by draupnir's sanoid. Jellyfin adds it as a *second folder* in the Movies library; Radarr's root folder stays `library/movies` only, so promoting a keeper is a manual `mv .../library/movies/<Film> /mnt/nas/essentials/<Film>` (cross-dataset copy+delete — Radarr never manages it).
- **`/var/lib/<service>`** for static-user services: persisted via `environment.persistence."${config.hostSpec.persistFolder}".directories`.

## DynamicUser + persistence (asgard caveat)

Three modules in this stack use `DynamicUser = true`. On **midgard** (wipe-on-boot rootfs from `btrfs-luks-impermanence-disk.nix`) this combination is genuinely tricky: `StateDirectory` creates `/var/lib/private/<svc>` and bind-mounts it to `/var/lib/<svc>` on every boot, but a fresh boot wipes the underlying subvolume, and naïvely declaring `environment.persistence."/persist".directories = ["/var/lib/<svc>"]` races with systemd's first-boot migration logic. On asgard (this host) the rootfs is **not** wiped (`btrfs-disk-uefi.nix`, no `postDeviceCommands`), so `/var/lib/private/<svc>` just sits there persistently and the trap is moot. The three modules and how we treat them here:

- `services.prowlarr` — module **does** expose `dataDir`, but **we deliberately leave it at the default**. A custom `dataDir` makes the module (a) bind-mount it onto `/var/lib/private/prowlarr` and (b) drop a tmpfiles rule that forces the bind source to `root:root 0700` on every tmpfiles run. On a non-wipe host like asgard the DynamicUser StateDirectory persists fine on its own, so the bind buys nothing — and the tmpfiles rule actively *breaks* the service: it periodically strips uid-61654's traverse permission on its own data dir, producing recurring `SQLite error (14): EACCES` and a DryIoc `ArrayTypeMismatchException` in the web UI (the data ends up owned by the parked `nobody`/65534 uid). We accept `/var/lib/private/prowlarr` as-is; it persists naturally on asgard, exactly like seerr. **No `environment.persistence` declaration.** (Lesson learned 2026-06-15 — the old "override dataDir to /srv" advice was wrong.)
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
shape changes between releases and isn't worth chasing. **Jellyfin now runs on
draupnir**, so walk through the wizard on the draupnir instance
(`https://jellyfin.lan.valgrindr.net`): create an admin user, enable HW
transcode (Dashboard → Playback → QuickSync/VAAPI, `/dev/dri/renderD128`), and
point the Movies library at the **local** `/tank/media/library/movies` **and**
`/tank/essentials`, Shows at `/tank/media/library/series`, Music at
`/tank/media/library/music`. State persists naturally.

Then seed the same creds in **asgard's** sops (Seerr lives here) so the
boot-time reconciler can drive Seerr's own first-run wizard via
`/api/v1/auth/jellyfin` against the draupnir edge:

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

### 3. NAS mount (done — draupnir tank over NFSv4)

The library lives on draupnir (`tank/media` + `tank/essentials`), exported to
asgard alone (`hosts/draupnir/services/nfs.nix`) and mounted by `storage.nix` as
two NFSv4 automounts (`/mnt/nas/media`, `/mnt/nas/essentials`). Verify:
`systemctl status mnt-nas-media.automount`, then `sudo -u sonarr touch
/mnt/nas/media/library/series/.probe`. The `media` gid is pinned to **1500** on
both hosts (numeric NFS mapping). Sonarr/Radarr root folders
(`/mnt/nas/media/library/{series,movies}`) are declared by the reconciler;
Jellyfin's library paths are set once in the UI (Bootstrap §2).

### 4. Activate the import

Uncomment `./media` in `hosts/asgard/services/default.nix` and deploy. The Mullvad namespace comes up immediately at activation; per-service WebUIs become reachable through asgard's own Caddy vhosts (`media/caddy.nix`) as soon as each unit starts.

## Ingress (per-host-caddy Phase 4)

Every WebUI is fronted by **asgard's own Caddy** (`services.caddyNjalla`, wildcard LE via Njalla DNS-01). bifrost is no longer in the request path — it only answers DNS. The wiring is:

- `hosts/asgard/services/media/caddy.nix` — five vhosts (Jellyfin's moved to draupnir's Caddy). Unconfined service (Seerr) → `127.0.0.1:5055`; confined services (qBittorrent, Prowlarr, Sonarr, Radarr) → the netns veth IP `192.168.15.1:<port>` (see the topology note above for why loopback won't work for those). **Seerr is special-cased**: it adds `bind 192.168.1.54 100.64.0.15` so it also listens on asgard's tailnet IP, putting it on the same guest-reachable `asgard:443` listener as Fluxer (so `group:guest` can submit requests). Every other media vhost stays LAN-IP-only via `services/caddy.nix` `default_bind`.
- `hosts/bifrost/services/dns.nix` — six AdGuard rewrites. Five point each `*.lan.valgrindr.net` name at **asgard's LAN IP** (`192.168.1.54`); **`seerr` points at asgard's tailnet IP** (`100.64.0.15`) so it lands on the guest-reachable tailnet listener (requires the client be on the tailnet — all our devices are).
- `hosts/bifrost/services/homepage.nix` — "Media (asgard)" group with all six tiles (URLs unchanged).

No firewall holes: backends are either loopback or the netns veth, both reachable only from asgard itself. Until `./media` is active on asgard, the vhosts 502 cosmetically — that's expected scaffold-mode behaviour.

## Inter-service wiring

The *arrs talk to each other (Prowlarr syncs indexers to Sonarr/Radarr; Sonarr/Radarr push downloads to qBittorrent; Seerr forwards requests to Sonarr/Radarr). All those connections are **runtime** — they live in each service's SQLite DB, not in Nix.

We do **not** pre-seed API keys via sops: the *arrs generate them on first boot inside their `config.xml`. Two consumers read those keys back:

- **Recyclarr** — its own pre-service oneshot (`recyclarr-credentials.service`) extracts and stages keys under `/var/lib/recyclarr-credentials/`, then systemd's `LoadCredential=` feeds them to recyclarr.
- **`bootstrap.nix` reconciler** — `media-bootstrap.service`, a Python oneshot running as root **inside the mullvad netns** (so `127.0.0.1:<port>` reaches the confined *arrs; PREROUTING DNAT doesn't fire on host-local loopback). Extracts keys live from each `config.xml` (and Seerr's `settings.json`), then idempotently REST-configures:
  - **Prowlarr → Sonarr / Radarr** (`/api/v1/applications`) so indexers cascade automatically.
  - **Prowlarr public indexers** (`/api/v1/indexer/schema` → `/api/v1/indexer`) — auto-enables a curated allow-list of Cardigann definitions that don't need auth (currently just Internet Archive). New indexers cascade to Sonarr/Radarr via the Apps registration above. Private / API-key indexers are deliberately not declared — they belong in the Prowlarr UI so secrets don't end up in the reconciler.
  - **Sonarr → qBittorrent** (`/api/v3/downloadclient`) with category `tv-sonarr`.
  - **Radarr → qBittorrent** with category `movies-radarr`.
  - **Sonarr / Radarr root folders** (`/api/v3/rootfolder`) — declares `/mnt/nas/media/library/series` and `/mnt/nas/media/library/movies` as the library targets. These are the NFSv4 automount off draupnir's `tank/media`; the setgid dirs are created on draupnir (`nfs.nix`).
  - **Auth bypass on the *arrs** (`/api/v{3,1}/config/host`) — sets `authenticationMethod=forms` + `authenticationRequired=disabledForLocalAddresses` and seeds an admin user (`admin` / password from sops `media/arr-admin-password`). Traffic via asgard's Caddy reaches the confined *arrs at the netns veth, so the source is `192.168.15.5` (the `mullvad-br` bridge) which is RFC1918 — the *arrs treat it as "local" and skip the form regardless of original client (same collapse the old bifrost path had). **qBittorrent** is handled separately and natively: its `AuthSubnetWhitelist` covers LAN + tailnet + loopback + the bridge `192.168.15.0/24` (`qbittorrent.nix`), no reconciler step needed.
  - **Seerr first-run wizard** (`/api/v1/auth/jellyfin` → `/api/v1/settings/jellyfin` → `/api/v1/settings/initialize`) — if `media/jellyfin-admin-{username,password}` are set in sops, the host-side reconciler logs into Jellyfin via Seerr, creates the mirror admin user, persists the Jellyfin connection (including `externalHostname = https://jellyfin.lan.valgrindr.net` for UI deep-links), and flips `public.initialized`. Jellyfin's own first-run wizard is **not** automated — its `/Startup/...` API is version-fragile, so we leave that as a single manual step (see Bootstrap §2). Skip the sops seed and the reconciler logs + moves on; Seerr's wizard can be done manually instead.
  - **Seerr → Sonarr / Radarr** (`/api/v1/settings/sonarr` and `/api/v1/settings/radarr`) — runs after the wizard auto-run (or whenever `settings.json.initialized = true`). Reconciled via the public edge URLs (`sonarr.lan.valgrindr.net:443` / `radarr.lan.valgrindr.net:443`, now answered by asgard's own Caddy) because Seerr lives in the main netns and PREROUTING DNAT to the Mullvad netns only fires for incoming connections — so it can't shortcut to `127.0.0.1`, it goes back out through Caddy.

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

**`single-request-reopen` (intermittent `EAI_AGAIN`).** With a *single* tunnel-routed resolver in a dual-stack netns, glibc fires the A and AAAA queries in parallel from one socket; over the WireGuard tunnel one reply intermittently gets dropped, so `getaddrinfo` returns `EAI_AGAIN` and every confined .NET app surfaces it as `SocketException (11): Resource temporarily unavailable (<host>:443)` — Prowlarr indexer tests fail, Radarr's SkyHook metadata lookups 503, and a Seerr request that hits the 503 gets marked **FAILED** (the request itself is fine — re-request and it goes through). `vpn.nix` appends `options single-request-reopen` to `/etc/netns/mullvad/resolv.conf` via an `ExecStartPost` on `mullvad.service` (re-applied every (re)start because `mullvad-up` does `rm -rf /etc/netns/mullvad` first), forcing the two lookups to run sequentially on separate sockets. We can't add a fallback nameserver — the netns firewall drops UDP/53 to anything but the configured resolver. If flakiness persists, the next lever is a small caching forwarder (dnsmasq/unbound) bound on the netns loopback, or `timeout:`/`attempts:` resolver options.

**Stale .NET resolver state after a netns restart (needs a service restart, not just a retry).** A `curl` recovers from the `EAI_AGAIN` race on the next attempt, but the *arrs don't: if a confined .NET app (Prowlarr especially) starts or queries *during* the window when `mullvad.service` is re-initializing the netns (e.g. right after a deploy that restarts the confined stack), it can cache the failed DNS/connection state in its SocketsHttpHandler pool and keep failing indefinitely — indexer tests error with `Resource temporarily unavailable (<host>:443)` even though `ip netns exec mullvad curl https://<host>` returns 200 and `am.i.mullvad.net/json` shows connected. Fix: `systemctl restart prowlarr` (or the affected *arr). Confirmed 2026-07-26 after the NFS/gid deploy — the fix restarted sonarr/radarr/qbittorrent but not prowlarr, which stayed stuck until restarted. Diagnostic that isolates it: egress works (`curl` 200 + Mullvad connected + fresh `wg` handshake) but the app still fails → it's stale app state, restart it. (Don't chase IPv6 — most indexers are IPv4-only; a `curl -6 … could not resolve` just means no AAAA record.)

**Durable fix (2026-08-11): `partOf = ["mullvad.service"]` on all four confined units** (`vpn.nix`, in the same `genAttrs` block as the resolv.conf bind). VPN-Confinement only sets `BindsTo`+`After`, which stops them when mullvad stops but does NOT recycle them when mullvad *restarts* — so netns churn left the .NET *arrs holding a poisoned SocketsHttpHandler pool. `PartOf` propagates mullvad's restart to them and `After=mullvad` orders them behind the resolv.conf write, so a deploy or `systemctl restart mullvad` now recycles them clean. The manual `systemctl restart <arr>` above is the fallback if one still wedges. Symptom this cured: deleting a Seerr request hung because Radarr 503'd its SkyHook lookup (`api.radarr.video` EAI_AGAIN) → Seerr logged `[Radarr] Failed to remove movie: Movie not found`.

## Adding a new service to this stack

1. Drop a file in this folder, listing it in `default.nix`.
2. Decide: confined or unconfined? If confined, add `systemd.services.<name>.vpnConfinement = { enable = true; vpnNamespace = "mullvad"; }` and an entry to `vpnNamespaces.mullvad.portMappings` (the mapping doubles as the in-namespace INPUT ACCEPT that lets local Caddy reach the veth).
3. No firewall hole — backends listen on loopback (unconfined) or the netns veth (confined); only Caddy reaches them.
4. Add a vhost to `media/caddy.nix`: unconfined → `reverse_proxy 127.0.0.1:<port>`; confined → `reverse_proxy 192.168.15.1:<port>`.
5. Add an AdGuard rewrite in `hosts/bifrost/services/dns.nix` pointing the name at `192.168.1.54` (asgard).
6. Add a Homepage tile in the "Media (asgard)" group in `hosts/bifrost/services/homepage.nix`.
7. Decide on persistence: static user → straight `environment.persistence`; DynamicUser → check for a `dataDir`-style escape hatch first. If none, accept ephemeral and add a TODO.
8. If it has an API key the reconciler needs, add an extractor to that pipeline.

## Recovery cheats

- **Service starts but the WebUI 502s through Caddy**: for a confined service, confirm Caddy can reach the veth — `curl -sI http://192.168.15.1:<port>` from asgard's main netns should answer. `ip netns exec mullvad ss -ltnp` shows what's actually listening inside the namespace; the `portMappings` entry must still be declared (it installs the in-namespace veth INPUT ACCEPT). For an unconfined service, `curl -sI http://127.0.0.1:<port>`.
- **Sonarr/Radarr can't reach qBittorrent**: confirm both are in the `mullvad` namespace (`systemctl show <svc> | grep NetworkNamespacePath`). The download client URL must be `http://127.0.0.1:8080` (namespace loopback), not the host IP.
- **Recyclarr fails with "401 Unauthorized"**: `recyclarr-credentials.service` ran but staged a stale or wrong key. `journalctl -u recyclarr-credentials` will show the extraction; verify the `<ApiKey>` element in `/var/lib/sonarr/.config/NzbDrone/config.xml` matches the running instance.
- **Bootstrap reconciler reports `POST … failed (401|403)`**: the *arr's API key extracted from `config.xml` doesn't match what the running instance expects (typically because the *arr restarted and rolled its key after `media-bootstrap.service` started but before it raced ahead). Run `systemctl restart media-bootstrap` manually; if it persists, check `<ApiKey>` ↔ running-state alignment via the *arr's UI.
- **Bootstrap reconciler reports `TIMEOUT waiting`**: a *arr exceeded the 180s readiness window. Either the service crashed (`systemctl status <svc>`) or boot-time DB migrations are running long; rerun `systemctl restart media-bootstrap` after the service settles.
- **Sonarr/Radarr show "qBittorrent: 401" in their download client tests**: qBittorrent's `AuthSubnetWhitelist` doesn't include `127.0.0.1/32`. Verify in `qbittorrent.nix` and that the WebUI conf was actually re-rendered (the module only re-writes `qBittorrent.conf` when changed).
- **qBittorrent WebUI unreachable; unit goes `active`→`inactive` in ~1s, log shows `qBittorrent termination initiated` / `ready to exit` right after `started` (exit 0)**: stale single-instance **lockfile** at `/var/lib/qBittorrent/qBittorrent/config/lockfile`, left behind when qBittorrent was `SIGKILL`ed (a deploy/restart whose stop exceeded the timeout — likely during a cascade of restarts). Every new instance sees the lock, thinks another copy is running, and quits. Restarting `mullvad` does NOT fix it (the lock lives in the profile, not the netns). Fix: `sudo systemctl stop qbittorrent && sudo rm -f /var/lib/qBittorrent/qBittorrent/config/lockfile && sudo systemctl start qbittorrent`, then confirm `ip netns exec mullvad ss -ltn | grep :8080`. Seen 2026-07-26 after the NFS/gid deploy churn.
- **`media/mullvad-wg-conf` decryption fails**: usual sops drift — `sops updatekeys hosts/asgard/secrets.yaml`. Until decryption succeeds, the namespace fails to come up and every confined service hangs in `activating (auto-restart)`.
- **Downloads piling up on /srv**: with `Move` semantics, the source should be deleted right after the *arr import. If they're not, the *arr's "Failed to import" log has the reason — usually a permissions issue on the NAS mount or a category mismatch with qBittorrent.
- **Seerr login fails with "the provided Jellyfin is invalid or the server is not reachable"**: Seerr's stored Jellyfin connection (`settings.jellyfin`) has drifted from the loopback target. Two seen failure modes: (a) `settings.jellyfin.ip` empty → `seerr` journal logs `hostname: http://undefined:undefinedundefined`; (b) `port: 80` + `useSsl: null` → it points at a dead address. `getHostname()` builds the server URL from `{useSsl, ip, port, urlBase}`, so either kills every login *before* credentials are checked. Compounding it, Seerr only reads `settings.json` at startup, so a corrected file does nothing until Seerr restarts. The wizard auto-run in `bootstrap.nix` is gated on `initialized=false` and can't fix an already-initialized stack; `ensure_jellyfin_connection()` in the seerr reconciler now **enforces** `ip=jellyfin.lan.valgrindr.net port=443 useSsl=true` (the draupnir Caddy edge, since Jellyfin moved off-host 2026-07-26 — correcting drift, not just empty values) and bounces Seerr. Trigger by hand: `systemctl restart media-bootstrap-seerr`, then watch `journalctl -u media-bootstrap-seerr` for `connection drift … → …; rewriting settings.json` followed by `connection repaired`. Field-name gotcha: the settings key is `ip` (not `hostname`) — `/api/v1/auth/jellyfin` takes `hostname` and maps it to `ip`, but `/api/v1/settings/jellyfin` and `settings.json` use `ip` directly.
