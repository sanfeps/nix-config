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
  - Home Assistant binds to `127.0.0.1:8123` and is fronted by asgard's local Caddy at `https://home.lan.valgrindr.net` (per-host-caddy Phase 2b). AdGuard rewrites the name directly to `192.168.1.54`; bifrost is not in the request path. `trusted_proxies` is `127.0.0.1`/`::1` only — Caddy is local so no cross-host hop to trust.
- **`immich.nix`** — self-hosted photo/video library at `https://immich.lan.valgrindr.net`. Native NixOS module, binds `127.0.0.1:2283`, fronted by asgard's local Caddy (per-host-Caddy Phase 1). AdGuard rewrites `immich.lan.valgrindr.net` → `192.168.1.54` directly; bifrost is not in the request path. Photo library lives at `/mnt/nas/immich`, which is **pre-NAS** backed by a local tmpfiles dir (see header of the file); once the NAS lands, uncomment the fileSystems block and drop the tmpfiles entries — the same path gets overlaid by NFS with no service-side change. Service state (DB rows, thumbnails, encoded video, ML models) lives under `/var/lib/immich` (persisted), photo originals under the mediaLocation. Machine-learning is on by default — CPU-heavy, revisit if asgard struggles.
- **`media/`** — see `services/media/CLAUDE.md` for the full media stack (Jellyfin, Seerr, Sonarr/Radarr/Prowlarr in a Mullvad netns, qBittorrent, Recyclarr).

## Tailnet client

Asgard imports `hosts/optional/tailscale.nix` and enrols into the `yggdrasil` tailnet via the autoconnect oneshot. Exit-node role lives on bifrost now (`hosts/optional/tailscale-exit-node.nix`); asgard is a plain client.

## Caddy

Asgard runs its own Caddy via the shared `services.caddyNjalla` module (`modules/nixos/services/caddy-njalla.nix`) with a wildcard LE cert for `*.lan.valgrindr.net` via Njalla DNS-01. Service modules declare their own `services.caddy.virtualHosts.*` inline. Asgard listens on `:80`/`:443` to the LAN.

Per-host-Caddy migration status (`docs/per-host-caddy-migration-plan.md`):

- **Immich** — fronted by local Caddy (Phase 1 ✓).
- **Ghostfolio** — fronted by local Caddy (Phase 2a ✓).
- **Home Assistant** — fronted by local Caddy (Phase 2b ✓).
- **Firefly III** — fronted by local Caddy (Phase 3 ✓). Caddy terminates TLS and proxies straight to the PHP-FPM Unix socket.
- **Media stack** (Jellyfin, Seerr, qBittorrent, Prowlarr, Sonarr, Radarr) — fronted by local Caddy (Phase 4 ✓). Vhosts in `services/media/caddy.nix`; the four Mullvad-confined services are proxied to the netns veth IP `192.168.15.1:<port>`. See `services/media/CLAUDE.md`. `media-proxies.nix` on bifrost is deleted.

## Deploys

Remote-build pattern from a workstation:

```bash
NIX_SSHOPTS="-i ~/.ssh/lykill" nixos-rebuild switch --flake .#asgard \
  --target-host sanfe@192.168.1.54 --build-host sanfe@192.168.1.54 \
  --ask-sudo-password
```

`trusted-users` is intentionally not granted on workstations: rely on `--build-host`.

## Recovery cheats

- **Caddy 502 on a vhost (from outside)**: every asgard app (Immich, Ghostfolio, Home Assistant, Firefly) now terminates TLS on asgard — check `systemctl status caddy` + `journalctl -u caddy -n 100` here. Only bifrost-local names (adguard, homepage, headplane, headscale) terminate on bifrost.
- **`*.lan.valgrindr.net` not resolving from the LAN**: AdGuard on bifrost (`192.168.1.55`) owns LAN DNS. Check `nc -vz 192.168.1.55 53` from the client. The rewrite answer determines which host the request lands on — `192.168.1.54` for asgard apps, `192.168.1.55` for bifrost-local services.
