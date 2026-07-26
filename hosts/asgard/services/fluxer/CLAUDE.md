# fluxer

Self-hosted **Fluxer** (https://fluxer.app, repo `fluxerapp/fluxer`) — an AGPLv3
Discord alternative. **LAN + tailnet only**, at `https://fluxer.lan.valgrindr.net`.

## Guest access over the tailnet (without exposing other asgard apps)

Fluxer is shared with `group:guest` tailnet users, but asgard's `:443` is a single
SNI-routed listener for *all* apps and tailnet ACLs are L3/L4 — so "guests get only
Fluxer" can't be done by granting `asgard:443` to the shared listener. Instead we
carve out a **Fluxer-only listener on asgard's tailnet IP**:

- `services/caddy.nix` sets `default_bind 192.168.1.54` → every vhost binds the LAN
  IP only by default. `+ ip_nonlocal_bind=1` so Caddy can bind the tailnet IP even
  before tailscaled assigns it.
- This module's Fluxer vhost adds `bind 192.168.1.54 100.64.0.15` → Fluxer is the
  *only* site also listening on the tailnet IP `100.64.0.15:443`.
- `fluxer.lan.valgrindr.net` is rewritten to `100.64.0.15` (AdGuard, bifrost
  `dns.nix`) for everyone, so all clients hit the Fluxer-only socket at the
  canonical name+port — the `*.lan` wildcard cert still matches and Fluxer's baked
  `https://fluxer.lan.valgrindr.net:443` URLs stay valid. (Requires the client be
  on the tailnet; all our devices are.)
- headscale ACL grants `group:guest → asgard:443` (= `100.64.0.15:443`, Fluxer only).
  Guests have no route/grant to `192.168.1.0/24`, so asgard's other apps (which bind
  the LAN IP) are unreachable to them.

Guests still need a Fluxer **account**: keep the instance invite-only (`/admin` →
registration mode) and hand out admin invite URLs. Enroll their device as the
headscale `guest` user (`headscale preauthkeys create --user guest --expiration 24h`).

## Why this is the one docker-compose in the repo

Fluxer has **no native nixpkgs package/module** and ships only as a ~22-container
Docker Compose stack (`docs.fluxer.app/operator`). It's too large and changes too
fast to hand-port to `oci-containers`, so we **vendor the upstream compose files
verbatim** and run them via `podman-compose` under a declarative systemd unit.
This is a deliberate, documented exception to the "no docker-compose inside Nix"
rule in `../media/CLAUDE.md` — that rule held because the media stack had native
NixOS services; Fluxer has none.

## File map

- `docker-compose.yml` — vendored from `github.com/fluxerapp/fluxer`
  `deploy/self-hosting`. **One LOCAL PATCH** (marked inline): the `caddy` service
  publishes `127.0.0.1:8080:80` instead of upstream's `80:80`/`443:443`/`443:443/udp`,
  because asgard's own Caddy owns the host's `:80`/`:443`. Everything else verbatim.
- `Caddyfile`, `livekit.yaml` — vendored verbatim.
- `default.nix` — the Nix glue: sops secret decls, the `fluxer.env` sops template,
  the `fluxer.service` systemd unit (stages files into `/var/lib/fluxer`, runs
  `podman-compose up -d`), the Caddy vhost, and the LiveKit firewall ports.

## Architecture

```
client → https://fluxer.lan.valgrindr.net
  │ (AdGuard on bifrost answers 192.168.1.54)
  ▼
asgard Caddy (services.caddyNjalla, wildcard LE)
  └─ reverse_proxy 127.0.0.1:8080
       ▼
     Fluxer's bundled Caddy (container, HTTP-only, FLUXER_CADDY_SITE_ADDRESS=:80)
       ├─ /api/*      → api:8080
       ├─ /gateway*   → gateway:8080   (WebSocket)
       ├─ /media/*    → media-proxy:8080
       ├─ /livekit/*  → livekit:7880
       ├─ /admin*     → admin:8080
       ├─ static      → static-proxy:8080
       └─ (catch-all) → app-proxy:8080
     + infra: postgres, valkey, nats, meilisearch, seaweedfs(+init), livekit
     + svc shards: snowflakes, users, messages, unfurl (router + shard each), worker
```

LiveKit media binds host ports **7881/tcp + 7882/udp** (opened in the firewall for
LAN/tailnet voice). Web rides asgard's existing `:443`, so no extra web hole.

## One-time bootstrap (before uncommenting the import)

The `./fluxer` import in `../default.nix` stays **commented** until the secrets are
seeded — otherwise activation fails rendering the `fluxer.env` sops template.

1. **Generate secrets** (run locally; values never need to touch the repo):
   ```bash
   for k in postgres-password meili-master-key s3-secret-key sudo-mode-secret \
            connection-initiation-secret gateway-rpc-auth-token \
            media-proxy-secret-key admin-secret-key-base \
            admin-oauth-client-secret livekit-api-secret; do
     printf '%s: %s\n' "$k" "$(openssl rand -hex 32)"
   done
   printf 'media-proxy-upload-relay-secret-base64: %s\n' "$(openssl rand -base64 32)"
   nix run nixpkgs#nodePackages.web-push -- generate-vapid-keys   # → vapid-public-key / vapid-private-key
   ```
2. **Seed sops**: `sops hosts/asgard/secrets.yaml`, add the values under a `fluxer:`
   block (keys = the names above, matching `sops.secrets."fluxer/<name>"` in
   `default.nix`).
3. **Uncomment** `./fluxer` in `../default.nix`.
4. **(Recommended)** bump the Proxmox VM to ≥4 vCPU / ≥8 GB RAM first — upstream's
   floor for an active community, on top of asgard's existing load.
5. **Deploy** asgard (remote-build pattern). First start pulls ~15 images +
   honours the api 90s healthcheck `start_period`; `TimeoutStartSec=1800`.

## Operations

- Status: `systemctl status fluxer`; containers: `podman ps`; logs:
  `podman logs fluxer-api-1` (etc.) or `journalctl -u fluxer`.
- Restart whole stack: `systemctl restart fluxer` (re-runs `podman-compose up -d`).
- Health via the bundled Caddy:
  `curl -s -H 'Host: fluxer.lan.valgrindr.net' http://127.0.0.1:8080/api/_health`.
- **First account registered becomes owner/admin** (`/admin`). Register it before
  sharing the URL.
- Upgrades: `FLUXER_IMAGE_TAG` is pinned to `v1` (tracks latest compatible) in the
  `fluxer.env` template; `cd /var/lib/fluxer && podman-compose pull && systemctl restart fluxer`.
  When upstream changes the compose file, re-vendor it here and re-apply the caddy
  ports patch.

## Persistence & backups

State lives in podman named volumes (`postgres-data`, `seaweedfs-data`,
`meilisearch-data`, `nats-data`, `caddy-{data,config}`) under
`/var/lib/containers/storage/volumes/` — durable on asgard (rootfs is **not**
wiped; see root CLAUDE.md). `/var/lib/fluxer/` is re-staged from the nix store +
sops on every start, so it needs no backup. **Back up** `postgres-data` and
`seaweedfs-data` (DB + uploaded media) if this becomes load-bearing; secrets are
already in sops.

## Gotchas

- **Caddy port collision** is the whole reason for the compose patch — never let
  Fluxer's bundled Caddy bind `:80`/`:443` on the host.
- **podman-compose vs compose semantics**: the stack leans on `depends_on` with
  `condition: service_healthy`/`service_completed_successfully`. podman-compose
  1.5.0 honours these (verified — it orders the ~22 services correctly).
- **Nested `${VAR:-...${VAR2}...}` interpolation is NOT supported by
  podman-compose 1.5.0** — it stops at the first `}` and emits a stray brace
  (e.g. image `ghcr.io/fluxerapp}/fluxer-api`, "invalid reference format"). The
  vendored `docker-compose.yml` flattens the affected lines (image refs +
  `FLUXER_VAPID_EMAIL`) to single-level `${VAR}` and relies on the `.env` always
  defining them — see the LOCAL PATCH header in that file. **Re-apply when
  re-vendoring from upstream.** If a future upstream adds more nested defaults,
  either flatten them or switch the unit to the `podman compose` provider.
- **Voice needs `FLUXER_LIVEKIT_URL`**: upstream's self-hosting compose OMITS it, so
  the backend never learns the client-facing LiveKit endpoint — voice rooms can't be
  allocated and joining a voice channel silently fails (the `VoiceReconciliationWorker`
  logs `liveKitServersSearched: 0`, and *nothing* reaches the livekit container — not a
  network/mic problem). `docker-compose.yml` adds `FLUXER_LIVEKIT_URL: wss://${FLUXER_DOMAIN}/livekit`
  (LOCAL PATCH) — the browser-facing WS URL the bundled Caddy proxies (`/livekit/*` →
  `livekit:7880`). This is separate from `node_ip` below (URL = signaling, node_ip = media).
- **Voice (LiveKit) IP**: LiveKit runs in the podman bridge namespace, so it can't
  see asgard's `tailscale0` and STUN only finds the WAN IP — neither reachable by
  clients. `livekit.yaml` pins `use_external_ip: false` + `node_ip: 100.64.0.15`
  (asgard's tailnet IP) so it advertises a routable media candidate; media UDP 7882
  / TCP 7881 are published on the host's `0.0.0.0`, so packets to `100.64.0.15:7882`
  over the mesh reach the container. Works for any tailnet client. **Guest voice**
  additionally needs `asgard:7881` + `asgard:7882` in the `group:guest` ACL
  (`hosts/bifrost/services/headscale.nix`) — admins already have `*:*`.
- Like any new service it needs the **AdGuard rewrite** in
  `hosts/bifrost/services/dns.nix` (`fluxer` → asgard) — already added.
