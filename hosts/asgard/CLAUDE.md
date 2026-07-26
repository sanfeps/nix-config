# asgard

Core app server. Proxmox VM on the home LAN.

- LAN IP: `192.168.1.54` (DHCP)
- Tailnet IP: `100.64.0.2` (`yggdrasil` tailnet, base domain `ts.yggdrasil.lo`, control plane on bifrost)
- Hardware: serial console preserved (`console=ttyS0`) for Proxmox recovery; root on `/dev/sda` with `btrfs-disk-uefi.nix` (plain BTRFS subvolumes, **no wipe-on-boot**, no LUKS — this is a VM). The `/persist` convention is still honoured for portability, but `/var/lib/<svc>` survives reboots regardless of `environment.persistence` declarations — see the root CLAUDE.md for the per-host impermanence breakdown.

Asgard used to also own networking (AdGuard, headscale, DDNS, exit-node). All of that moved to bifrost in the Phase 3 cutover. Asgard is now strictly an app server.

## Services

All live under `services/` and are wired in `services/default.nix`:

- **`finances/`** — shared PostgreSQL (TCP on `127.0.0.1` so containers can connect via `--network=host`) + per-app modules:
  - **Firefly III** at `https://firefly.lan.valgrindr.net` (native NixOS module, peer auth via socket, php_fastcgi via Unix socket). Fronted by asgard's local Caddy (per-host-caddy Phase 3): Caddy terminates TLS itself and talks straight to PHP-FPM's socket, so PHP sees a genuine https:// request — no more `env HTTPS on` / `env SERVER_PORT 443` lie, no trust-proxy plumbing. AdGuard rewrites the name directly to `192.168.1.54`; bifrost is not in the request path.
  - **Ghostfolio** (Podman container on TCP+scram auth, local Redis on `127.0.0.1:6379`). Container binds `127.0.0.1:3333` (via the module's `host` option) and is fronted by asgard's local Caddy at `https://ghostfolio.lan.valgrindr.net`. AdGuard rewrites the name directly to `192.168.1.54`; bifrost is not in the request path.
  - Secrets come from sops via `sops.templates` rendered into env / SQL files at activation. **Ghostfolio user accounts are not declarative**: passwordless model with server-side tokens stored hashed in Postgres (`Account` table). The current user's token is stashed in sops at `finances/ghostfolio-user-token` purely as a recovery aid — on a from-scratch rebuild, restore the Postgres dump (`/persist/var/backups/postgres/`) **before** logging in; if the DB is empty Ghostfolio mints a new token and the one in sops becomes useless.
  - **`fly-import`** CLI for Kutxabank PDFs.
  - **Backups**: `pg_dump` custom format daily, persisted at `/persist/var/backups/postgres/`, validated end-to-end (restorable).
- **`home-automation/`** — Home Assistant + Mosquitto.
  - Home Assistant is enabled via the reusable `homelab.services.homeAssistant` module (`modules/homelab/services/home-assistant/`); the host file only sets `name = "Asgard"`, the `url`, and the co-located mqtt broker via `extraConfig`. Binds `127.0.0.1:8123`, fronted by asgard's local Caddy at `https://home.lan.valgrindr.net` (per-host-caddy Phase 2b). AdGuard rewrites the name directly to `192.168.1.54`; bifrost is not in the request path. `trusted_proxies` is `127.0.0.1`/`::1` only — Caddy is local so no cross-host hop to trust. Mosquitto stays a separate host file.
- **`media/`** — see `services/media/CLAUDE.md` for the full media stack (Seerr, Sonarr/Radarr/Prowlarr in a Mullvad netns, qBittorrent, Recyclarr). **Jellyfin moved to draupnir 2026-07-26** for Quick Sync HW transcode (asgard's VM has no usable GPU); asgard still holds acquisition + Seerr + yt2jelly and NFS-mounts the library so the *arrs keep writing to it.
- **`fluxer/`** — self-hosted **Fluxer** (Discord alternative) at `https://fluxer.lan.valgrindr.net`. The **only docker-compose in the repo**: a ~22-container stack vendored verbatim and run via `podman-compose` under a declarative systemd unit (no native nixpkgs option exists). Fluxer's bundled Caddy is loopback-only HTTP (`127.0.0.1:8080`) and asgard's own Caddy fronts it; LiveKit voice binds 7881/tcp + 7882/udp (LAN/tailnet). Import in `services/default.nix` stays **commented** until the `fluxer/*` sops secrets are seeded — see `services/fluxer/CLAUDE.md` for the one-time bootstrap, the compose patch, and ops/backup notes.

## Tailnet client

Asgard imports `hosts/optional/tailscale.nix` and enrols into the `yggdrasil` tailnet via the autoconnect oneshot. Exit-node role lives on bifrost now (`hosts/optional/tailscale-exit-node.nix`); asgard is a plain client.

## Caddy

Asgard runs its own Caddy via the shared `services.caddyNjalla` module (`modules/nixos/services/caddy-njalla.nix`) with a wildcard LE cert for `*.lan.valgrindr.net` via Njalla DNS-01. Service modules declare their own `services.caddy.virtualHosts.*` inline. Asgard listens on `:80`/`:443` to the LAN.

`services/caddy.nix` pins `default_bind 192.168.1.54`, so every vhost binds the **LAN IP only** — except the vhosts that opt into also binding asgard's **tailnet IP** with `bind 192.168.1.54 100.64.0.2`: currently **Fluxer** (`services/fluxer/default.nix`) and **Seerr** (`services/media/caddy.nix`). That makes `100.64.0.2:443` a guest-reachable listener serving only those two, so `group:guest` tailnet users (granted `asgard:443`) reach Fluxer + Seerr and nothing else; the other apps stay on the LAN IP (reachable on-LAN, and off-LAN to admins via bifrost's `192.168.1.0/24` subnet route). Each tailnet-bound name is rewritten to `100.64.0.2` in bifrost's AdGuard so all clients land on that listener. `ip_nonlocal_bind=1` lets Caddy bind the tailnet IP without waiting on tailscaled. See `services/fluxer/CLAUDE.md`.

Per-host-Caddy migration status (`docs/per-host-caddy-migration-plan.md`):

- **Immich** — was Phase 1 here; moved to draupnir 2026-07 (fresh install, the asgard instance was empty scaffold — `docs/immich-draupnir-migration-runbook.md`). Leftover state on asgard (`/mnt/nas/immich`, `/var/lib/immich`, the `immich` Postgres DB) can be cleaned whenever.
- **Ghostfolio** — fronted by local Caddy (Phase 2a ✓).
- **Home Assistant** — fronted by local Caddy (Phase 2b ✓).
- **Firefly III** — fronted by local Caddy (Phase 3 ✓). Caddy terminates TLS and proxies straight to the PHP-FPM Unix socket.
- **Media stack** (Jellyfin, Seerr, qBittorrent, Prowlarr, Sonarr, Radarr) — fronted by local Caddy (Phase 4 ✓). Vhosts in `services/media/caddy.nix`; the four Mullvad-confined services are proxied to the netns veth IP `192.168.15.1:<port>`. See `services/media/CLAUDE.md`. `media-proxies.nix` on bifrost is deleted.
- **Fluxer** — fronted by local Caddy. Vhost in `services/fluxer/default.nix` reverse-proxies `127.0.0.1:8080` (Fluxer's bundled, loopback-only Caddy, which then does internal path routing). See `services/fluxer/CLAUDE.md`.

## Deploys

Remote-build pattern from a workstation:

```bash
NIX_SSHOPTS="-i ~/.ssh/lykill" nixos-rebuild switch --flake .#asgard \
  --target-host sanfe@192.168.1.54 --build-host sanfe@192.168.1.54 \
  --ask-sudo-password
```

`trusted-users` is intentionally not granted on workstations: rely on `--build-host`.

## Recovery cheats

- **Caddy 502 on a vhost (from outside)**: every asgard app (Ghostfolio, Home Assistant, Firefly, the media stack minus Jellyfin) terminates TLS on asgard — check `systemctl status caddy` + `journalctl -u caddy -n 100` here. **`jellyfin.lan` now terminates on draupnir** (`192.168.1.56`) — check Caddy there. Only bifrost-local names (adguard, homepage, headplane, headscale) terminate on bifrost.
- **`*.lan.valgrindr.net` not resolving from the LAN**: AdGuard on bifrost (`192.168.1.55`) owns LAN DNS. Check `nc -vz 192.168.1.55 53` from the client. The rewrite answer determines which host the request lands on — `192.168.1.54` for asgard apps, `192.168.1.55` for bifrost-local services.
