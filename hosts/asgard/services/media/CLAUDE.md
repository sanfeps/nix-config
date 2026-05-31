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
- `seerr.nix` — outside the netns. **No persistence** (StateDirectory is `jellyseerr` and there's no `dataDir` escape hatch — see notes).
- `recyclarr.nix` — outside the netns. Pre-service oneshot stages API keys from each *arr's `config.xml`.
- `bootstrap.nix` — boot-time reconciler (Python oneshot, root). Idempotently registers Sonarr/Radarr in Prowlarr and configures qBittorrent as the download client on both *arrs. Does NOT touch Seerr (impermanence trap) or root folders (NAS not provisioned). See "Inter-service wiring" below for the data flow.

## Storage decisions

- **`/srv/media/downloads`** (ephemeral, on /persist via /srv being a regular subvolume): qBittorrent's `DefaultSavePath`. Sonarr/Radarr `Move` (not `Hardlink`) imports from here to the library on the NAS, then delete the source. We're a Mullvad leecher (no port forwarding), so seeding is impossible — there's nothing to preserve cross-host or cross-reboot. **No NAS round-trip for downloads.**
- **`/mnt/nas/media/library`** (NAS-mounted, NFS): final media library, mounted read-write for the *arrs to write into, read-only for Jellyfin (group `media`). Until the NAS lands, `storage.nix` backs this path with local tmpfiles dirs (`library/{tv,movies}`, group `media`, mode 0775) so the full workflow can be validated end-to-end on local disk. When the NAS lands, uncomment the `fileSystems."/mnt/nas/media"` block and drop the `TEMP(no-nas)` tmpfiles lines — NFS overlays the same path, so nothing else in the stack changes.
- **`/srv/media/state/prowlarr`** — only because the upstream `prowlarr` module uses `DynamicUser` (see below).
- **`/var/lib/<service>`** for static-user services: persisted via `environment.persistence."${config.hostSpec.persistFolder}".directories`.

## DynamicUser persistence trap (very important)

Three modules in this stack use `DynamicUser = true`:

- `services.prowlarr` — module **does** expose `dataDir`. Setting it to a non-default path causes the module to create a bind mount instead of relying on `StateDirectory`. We use `/srv/media/state/prowlarr`. ✅ Persistence works.
- `services.seerr` — module **does not** expose `dataDir`. Overriding `configDir` breaks startup (nixpkgs issue #457739). Naïvely persisting `/var/lib/jellyseerr` collides with systemd's first-boot `/var/lib/private` migration. ⚠️ **Leave Seerr ephemeral.** Request history is lost on reboot — known limitation. A future `/var/lib/private` impermanence recipe (AdGuard precedent in the root CLAUDE.md) will fix this.
- AdGuard on bifrost has the same shape — it's the canonical example to crib from once a fix lands.

The other modules (`qbittorrent`, `sonarr`, `radarr`, `jellyfin`, `recyclarr`) use **static** users, so straight `environment.persistence` works.

## Bootstrap (one-time, manual)

The stack is fully declarative, but two things need a manual seed before the import comes off the commented list:

### 1. Mullvad WireGuard config

```bash
# Local: log into mullvad.net → WireGuard configuration generator,
# generate a key, pick ONE server, download the .conf.
# Edit it to confirm `DNS = 10.64.0.1` is under [Interface] (leak belt).
sops hosts/asgard/secrets.yaml   # add key: media/mullvad-wg-conf, value: full conf as multiline YAML
```

### 2. NAS mount (skip until NAS is provisioned)

Once the NAS exists at `nas.lan` (or wherever) exporting an NFS share:
1. Uncomment the `fileSystems."/mnt/nas/media"` block in `storage.nix`.
2. Verify mount comes up: `systemctl status mnt-nas-media.automount`.
3. Point Sonarr/Radarr root folders + Jellyfin library at `/mnt/nas/media/library/{tv,movies}` via their respective UIs (the Phase 6 reconciler will eventually automate this).

### 3. Activate the import

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
- **`bootstrap.nix` reconciler** — `media-bootstrap.service`, a Python oneshot running as root after all *arrs come up. Extracts keys live from each `config.xml`, then idempotently REST-configures:
  - **Prowlarr → Sonarr / Radarr** (`/api/v1/applications`) so indexers cascade automatically.
  - **Sonarr → qBittorrent** (`/api/v3/downloadclient`) with category `tv-sonarr`.
  - **Radarr → qBittorrent** with category `movies-radarr`.

The reconciler is **best-effort**: any failed step is logged and skipped, the unit always exits 0. Inspect `journalctl -u media-bootstrap` after a deploy to see what landed.

Scoped out of the reconciler:
- **Seerr** — its state directory hits the DynamicUser impermanence trap (see `seerr.nix`). Configuring Seerr declaratively today just gets wiped on the next reboot, so wire it manually in the UI and accept the limitation.
- **Root folders** on Sonarr/Radarr — they need `/mnt/nas/media/library/{tv,movies}` to exist. Add via UI (or extend the reconciler) once the NAS lands.
- **Quality profiles / custom formats** — owned by recyclarr.

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
