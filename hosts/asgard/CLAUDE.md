# asgard

Core app server. Proxmox VM on the home LAN.

- LAN IP: `192.168.1.54` (DHCP)
- Tailnet IP: `100.64.0.2` (`yggdrasil` tailnet, base domain `ts.yggdrasil.lo`, control plane on bifrost)
- Hardware: serial console preserved (`console=ttyS0`) for Proxmox recovery; root on `/dev/sda` with btrfs + impermanence (no LUKS — this is a VM).

Asgard used to also own networking (AdGuard, headscale, DDNS, exit-node). All of that moved to bifrost in the Phase 3 cutover. Asgard is now strictly an app server.

## Services

All live under `services/` and are wired in `services/default.nix`:

- **`finances/`** — shared PostgreSQL (TCP on `127.0.0.1` so containers can connect via `--network=host`) + per-app modules:
  - **Firefly III** at `http://firefly.lan.valgrindr.net` (native NixOS module, peer auth via socket, php_fastcgi by Unix socket — that's why it stayed on asgard and isn't proxied from bifrost: Caddy can only reach the FPM socket on the same host).
  - **Ghostfolio** (Podman container on TCP+scram auth, local Redis on `127.0.0.1:6379`). Caddy on bifrost reverse-proxies `http://ghostfolio.lan.valgrindr.net` → `192.168.1.54:3333`. Firewall on asgard restricts port 3333 to source `192.168.1.55` (bifrost) only.
  - Secrets come from sops via `sops.templates` rendered into env / SQL files at activation. **Ghostfolio user accounts are not declarative**: passwordless model with server-side tokens stored hashed in Postgres (`Account` table). The current user's token is stashed in sops at `finances/ghostfolio-user-token` purely as a recovery aid — on a from-scratch rebuild, restore the Postgres dump (`/persist/var/backups/postgres/`) **before** logging in; if the DB is empty Ghostfolio mints a new token and the one in sops becomes useless.
  - **`fly-import`** CLI for Kutxabank PDFs.
  - **Backups**: `pg_dump` custom format daily, persisted at `/persist/var/backups/postgres/`, validated end-to-end (restorable).
- **`home-automation/`** — Home Assistant + Mosquitto.
  - Home Assistant binds to `0.0.0.0:8123`. Caddy on bifrost reverse-proxies `http://home.lan.valgrindr.net` → `192.168.1.54:8123`. Firewall on asgard restricts 8123 to source `192.168.1.55` only.
  - Home Assistant config has `bifrost (192.168.1.55)` in `trusted_proxies` so `X-Forwarded-For` headers surface real client IPs.

## Tailnet client

Asgard imports `hosts/optional/tailscale.nix` and enrols into the `yggdrasil` tailnet via the autoconnect oneshot. Exit-node role lives on bifrost now (`hosts/optional/tailscale-exit-node.nix`); asgard is a plain client.

## Caddy

There is **no Caddy on asgard anymore**. All public-facing TLS termination and LAN ingress is bifrost's job. Services on asgard simply listen on a port and rely on bifrost to proxy in over the LAN (with firewall lock-down from asgard's side restricting source to `192.168.1.55`).

## Deploys

Remote-build pattern from a workstation:

```bash
NIX_SSHOPTS="-i ~/.ssh/lykill" nixos-rebuild switch --flake .#asgard \
  --target-host sanfe@192.168.1.54 --build-host sanfe@192.168.1.54 \
  --ask-sudo-password
```

`trusted-users` is intentionally not granted on workstations: rely on `--build-host`.

## Recovery cheats

- **Caddy 502 on a vhost (from outside)**: vhost is on bifrost, not asgard. Check the bifrost Caddy logs and whether the backing service on asgard is reachable from `192.168.1.55` (firewall rule per service).
- **`*.lan.valgrindr.net` not resolving from the LAN**: AdGuard on bifrost (`192.168.1.55`) owns LAN DNS now. Check `nc -vz 192.168.1.55 53` from the client.
