# asgard

Core app server. Proxmox VM on the home LAN.

- LAN IP: `192.168.1.54` (DHCP)
- Tailnet IP: `100.64.0.2` (`yggdrasil` tailnet, base domain `ts.yggdrasil.lo`, control plane on bifrost)
- Hardware: serial console preserved (`console=ttyS0`) for Proxmox recovery; root on `/dev/sda` with `btrfs-disk-uefi.nix` (plain BTRFS subvolumes, **no wipe-on-boot**, no LUKS — this is a VM). The `/persist` convention is still honoured for portability, but `/var/lib/<svc>` survives reboots regardless of `environment.persistence` declarations — see the root CLAUDE.md for the per-host impermanence breakdown.

Asgard used to also own networking (AdGuard, headscale, DDNS, exit-node). All of that moved to bifrost in the Phase 3 cutover. Asgard is now strictly an app server.

## Services

All live under `services/` and are wired in `services/default.nix`:

- **`finances/`** — shared PostgreSQL (TCP on `127.0.0.1` so containers can connect via `--network=host`) + per-app modules:
  - **Firefly III** at `https://firefly.lan.valgrindr.net` (native NixOS module, peer auth via socket, php_fastcgi via Unix socket). TLS terminates on bifrost; bifrost proxies plain HTTP to asgard:80, where a tiny local Caddy translates HTTP→FastCGI to PHP-FPM's socket (the socket can't be reached across hosts, which is why asgard keeps Caddy at all). Caveat: trusted-proxy handling in Firefly is unreliable, so asgard's `php_fastcgi` lies to PHP with `env HTTPS on` + `env SERVER_PORT 443` — Symfony then thinks the connection is https and Laravel emits https:// URLs everywhere.
  - **Ghostfolio** (Podman container on TCP+scram auth, local Redis on `127.0.0.1:6379`). Caddy on bifrost reverse-proxies `http://ghostfolio.lan.valgrindr.net` → `192.168.1.54:3333`. Firewall on asgard restricts port 3333 to source `192.168.1.55` (bifrost) only.
  - Secrets come from sops via `sops.templates` rendered into env / SQL files at activation. **Ghostfolio user accounts are not declarative**: passwordless model with server-side tokens stored hashed in Postgres (`Account` table). The current user's token is stashed in sops at `finances/ghostfolio-user-token` purely as a recovery aid — on a from-scratch rebuild, restore the Postgres dump (`/persist/var/backups/postgres/`) **before** logging in; if the DB is empty Ghostfolio mints a new token and the one in sops becomes useless.
  - **`fly-import`** CLI for Kutxabank PDFs.
  - **Backups**: `pg_dump` custom format daily, persisted at `/persist/var/backups/postgres/`, validated end-to-end (restorable).
- **`home-automation/`** — Home Assistant + Mosquitto.
  - Home Assistant binds to `0.0.0.0:8123`. Caddy on bifrost reverse-proxies `http://home.lan.valgrindr.net` → `192.168.1.54:8123`. Firewall on asgard restricts 8123 to source `192.168.1.55` only.
  - Home Assistant config has `bifrost (192.168.1.55)` in `trusted_proxies` so `X-Forwarded-For` headers surface real client IPs.
- **`immich.nix`** — self-hosted photo/video library at `https://immich.lan.valgrindr.net`. Native NixOS module, binds `127.0.0.1:2283`, fronted by asgard's local Caddy (per-host-Caddy Phase 1). AdGuard rewrites `immich.lan.valgrindr.net` → `192.168.1.54` directly; bifrost is not in the request path. Photo library lives at `/mnt/nas/immich`, which is **pre-NAS** backed by a local tmpfiles dir (see header of the file); once the NAS lands, uncomment the fileSystems block and drop the tmpfiles entries — the same path gets overlaid by NFS with no service-side change. Service state (DB rows, thumbnails, encoded video, ML models) lives under `/var/lib/immich` (persisted), photo originals under the mediaLocation. Machine-learning is on by default — CPU-heavy, revisit if asgard struggles.
- **`media/`** — see `services/media/CLAUDE.md` for the full media stack (Jellyfin, Seerr, Sonarr/Radarr/Prowlarr in a Mullvad netns, qBittorrent, Recyclarr).

## Tailnet client

Asgard imports `hosts/optional/tailscale.nix` and enrols into the `yggdrasil` tailnet via the autoconnect oneshot. Exit-node role lives on bifrost now (`hosts/optional/tailscale-exit-node.nix`); asgard is a plain client.

## Caddy

Asgard runs its own Caddy via the shared `services.caddyNjalla` module (`modules/nixos/services/caddy-njalla.nix`) with a wildcard LE cert for `*.lan.valgrindr.net` via Njalla DNS-01. Service modules declare their own `services.caddy.virtualHosts.*` inline. Asgard listens on `:80`/`:443` to the LAN.

Per-host-Caddy migration status (`docs/per-host-caddy-migration-plan.md`):

- **Immich** — fronted by local Caddy (Phase 1 ✓).
- **Firefly III** — legacy: vhost still binds plain `:80` HTTP and bifrost terminates TLS in front of it; the PHP-FPM Unix socket bridge stays in `hosts/asgard/services/finances/firefly.nix` until Phase 3.
- **Ghostfolio** / **Home Assistant** — legacy: still listening on `:3333`/`:8123` with bifrost reverse-proxying. Phase 2 cuts them over.

## Deploys

Remote-build pattern from a workstation:

```bash
NIX_SSHOPTS="-i ~/.ssh/lykill" nixos-rebuild switch --flake .#asgard \
  --target-host sanfe@192.168.1.54 --build-host sanfe@192.168.1.54 \
  --ask-sudo-password
```

`trusted-users` is intentionally not granted on workstations: rely on `--build-host`.

## Recovery cheats

- **Caddy 502 on a vhost (from outside)**: figure out where the vhost terminates. For Immich and any future migrated service the answer is asgard (`systemctl status caddy` + `journalctl -u caddy -n 100`); for legacy services (Firefly, Ghostfolio, Home Assistant) it's still bifrost.
- **`*.lan.valgrindr.net` not resolving from the LAN**: AdGuard on bifrost (`192.168.1.55`) owns LAN DNS. Check `nc -vz 192.168.1.55 53` from the client. The rewrite answer determines which host the request lands on — asgard for migrated services, bifrost for legacy ones.
