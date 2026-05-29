# asgard

Core homelab server. Proxmox VM on the home LAN.

- LAN IP: `192.168.1.54` (DHCP)
- Tailnet IP: `100.64.0.1` (`yggdrasil` tailnet, base domain `ts.yggdrasil.lo`)
- Public DNS: `headscale.valgrindr.net` (Njalla DDNS, updated by `services/ddns.nix`)
- LAN zone: `lan.valgrindr.net` (resolved locally by AdGuard, not public)
- Hardware: serial console preserved (`console=ttyS0`) for Proxmox recovery; root on `/dev/sda` with btrfs + impermanence (no LUKS — this is a VM).

## Services

All live under `services/` and are wired in `services/default.nix`:

- **`ddns.nix`** — systemd timer that updates Njalla's A record for `headscale.valgrindr.net` from the host's public IP. Uses `sops.secrets."njalla-key-headscale"`.
- **`dns.nix`** — AdGuard Home (DNS + LAN-zone rewrites). See the root `CLAUDE.md` for the full DNS section; the gotchas (rewrites under `filtering`, port 53 not opened by `openFirewall`, `enabled = true` per rewrite, `DynamicUser` impermanence trap) are non-obvious — read them before editing.
- **`headscale.nix`** — self-hosted tailscale control plane fronted by Caddy on `headscale.valgrindr.net`. The `headscale-bootstrap` oneshot seeds the SQLite DB with the `yggdrasil` user and a reusable preauth key whose prefix+hash come from sops.
- **`finances/`** — shared PostgreSQL (TCP on `127.0.0.1` so containers can connect via `--network=host`) + per-app modules:
  - **Firefly III** at `http://firefly.lan.valgrindr.net` (native NixOS module, peer auth via socket).
  - **Ghostfolio** at `http://ghostfolio.lan.valgrindr.net` (Podman container, TCP+scram auth, local Redis on `127.0.0.1:6379`). Secrets come from sops via `sops.templates` rendered into env / SQL files at activation. **User accounts are not declarative**: Ghostfolio uses a passwordless model where each user's auth token is generated server-side at signup and stored hashed in Postgres (`Account` table). The current user's token is stashed in sops at `finances/ghostfolio-user-token` purely as a recovery aid — on a from-scratch rebuild of asgard, restore the Postgres dump (`/persist/var/backups/postgres/`) **before** logging in; if the DB is empty Ghostfolio will mint a new token and the one in sops becomes useless.
  - **`fly-import`** CLI for Kutxabank PDFs.
  - **Backups**: `pg_dump` custom format daily, persisted at `/persist/var/backups/postgres/`, validated end-to-end (restorable).
- **`home-automation/`** — Home Assistant + Mosquitto. Exposed via Caddy at `home.lan.valgrindr.net` / `mqtt.lan.valgrindr.net`.

## Exit node

Asgard se anuncia como Tailscale exit node (`services/tailscale-exit-node.nix`): `useRoutingFeatures = "server"` (NixOS habilita IP forwarding) + un oneshot `tailscale-advertise-exit-node` que aplica `tailscale set --advertise-exit-node=true` en cada boot/deploy. La aprobación es declarativa via `policy.path` en `headscale.nix` (`autoApprovers.exitNode` para el grupo del usuario `yggdrasil`), así que cualquier nodo enrolado en ese usuario que anuncie `0.0.0.0/0` + `::/0` queda aprobado sin pasar por `headscale nodes approve-routes`. Si añades subnet routers, mete su prefijo en `autoApprovers.routes` dentro del HuJSON del `policyFile`.

**Clientes**: el opt-in es manual y por-cliente, intencionadamente. Cuando estés fuera de casa en una red hostil:

```bash
tailscale set --exit-node=asgard --exit-node-allow-lan-access=true
# para volver:
tailscale set --exit-node=
```

No lo pongas como default en ningún cliente: en LAN degrada el throughput (todo el tráfico daría la vuelta por casa) y el upload del ISP se convierte en el cuello de botella cuando lo usas fuera.

## Caddy

A single Caddy instance fronts every web service. Vhosts are declared next to the service they front, **not** in a central caddy.nix. Always use the `http://` prefix on `services.caddy.virtualHosts."http://name.lan.valgrindr.net"` so Caddy doesn't try to provision a public TLS cert for a name that only resolves on the LAN.

Caddy persistence is configured in `services/headscale.nix` (it was the first service to need it). Don't redeclare `/var/lib/caddy` elsewhere.

## Pending / known TODOs

- AdGuard admin password is currently a hardcoded bcrypt in `services/dns.nix`. Move to a sops template once the YubiKey work lands.
- AdGuard state is intentionally ephemeral right now (filter lists redownload ~5min on boot) because `DynamicUser = true` conflicts with naive `/var/lib/AdGuardHome` impermanence. Re-add persistence by binding `/var/lib/private/AdGuardHome` once a clean recipe exists.
- Router DHCP should advertise `192.168.1.54` as the LAN DNS so non-tailnet devices also benefit from AdGuard. Not yet done.

## Deploys

Remote-build pattern from a workstation:

```bash
NIX_SSHOPTS="-i ~/.ssh/lykill" nixos-rebuild switch --flake .#asgard \
  --target-host sanfe@192.168.1.54 --build-host sanfe@192.168.1.54 \
  --ask-sudo-password
```

`trusted-users` is intentionally not granted on workstations: rely on `--build-host`.

## Recovery cheats

- **DNS dead on asgard itself** (AdGuard down + `nameservers = ["127.0.0.1"]`): SSH in and write a temporary `nameserver 9.9.9.9` to `/etc/resolv.conf`. The fallback in `dns.nix` (`9.9.9.9` as secondary) should prevent this, but it can still happen mid-rebuild.
- **Caddy 502 on a vhost**: check `systemctl status` for the backing service; vhost config is in the service's own `.nix`.
- **Tailnet member can't resolve `*.lan.valgrindr.net`**: AdGuard isn't reachable from the tailnet. Check `nc -vz 192.168.1.54 53` from the member; if it times out, port 53 isn't open on asgard's firewall (`networking.firewall.allowedTCPPorts`/`allowedUDPPorts`).
