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
- **`finances/`** — Firefly III + PostgreSQL + Kutxabank importer (`fly-import` CLI). Caddy fronts Firefly at `http://firefly.lan.valgrindr.net`. Backups: `pg_dump` custom format daily, persisted at `/persist/var/backups/postgres/`, validated end-to-end (restorable).
- **`home-automation/`** — Home Assistant + Mosquitto. Exposed via Caddy at `home.lan.valgrindr.net` / `mqtt.lan.valgrindr.net`.

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
