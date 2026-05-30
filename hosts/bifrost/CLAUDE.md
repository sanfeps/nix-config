# bifrost

Networking host. Proxmox VM on the home LAN. The rainbow bridge between Asgard (apps) and everything else — owns DNS, headscale, public ingress (TLS termination with LE wildcard via Njalla DNS-01), Njalla DDNS for `headscale.valgrindr.net`, and the tailnet exit-node role.

- LAN IP: `192.168.1.55` (static-at-OS via `networking.interfaces.ens18.ipv4.addresses` until the router supports DHCP reservations)
- Tailnet IP: `100.64.0.3` (`yggdrasil` tailnet, base domain `ts.yggdrasil.lo`)
- Public DNS: `headscale.valgrindr.net` (Njalla A record, updated by `services/ddns.nix`)
- LAN zone: `lan.valgrindr.net` (resolved locally by AdGuard, not public; wildcard LE cert covers `*.lan.valgrindr.net` via Njalla DNS-01)
- Hardware: serial console preserved (`console=ttyS0`); root on `/dev/sda` with btrfs + impermanence (VM, no LUKS).

## Services

Wired in `services/default.nix`:

- **`dns.nix`** — AdGuard Home. Bound to `0.0.0.0:53`, DoH upstream Quad9. WebUI on `127.0.0.1:3000`, reverse-proxied by Caddy at `https://adguard.lan.valgrindr.net`. LAN-zone rewrites point every `*.lan.valgrindr.net` name at bifrost (`192.168.1.55`); bifrost owns LAN TLS termination so even services running on asgard (Firefly, Ghostfolio, Home Assistant) get their public name pointed at bifrost and proxied across. `mutableSettings = false`: changes only via Nix.
- **`caddy.nix`** — Single Caddy instance with Njalla DNS-01 plugin (built via `pkgs.caddy.withPlugins`). Two top-level vhosts:
  - `headscale.valgrindr.net` (public): TLS via HTTP-01 on 80/443 forwarded by router → bifrost. Proxies to `127.0.0.1:8080`.
  - `*.lan.valgrindr.net` (wildcard, LE via DNS-01 with `acme_dns njalla {env.NJALLA_API_TOKEN}`): per-service routing via `@host` matchers + `handle` blocks. Adguard local (127.0.0.1:3000); Ghostfolio (192.168.1.54:3333); Home Assistant (192.168.1.54:8123); Firefly (192.168.1.54:80 — asgard runs a tiny Caddy that lies to PHP with `env HTTPS on` so Firefly emits https URLs). Fallback `respond "bifrost edge - unknown subdomain" 404`.
- **`headscale.nix`** — self-hosted Tailscale control plane. Listens `127.0.0.1:8080`, DERP STUN UDP `3478`. Pushes `192.168.1.55` (bifrost AdGuard) as DNS to tailnet members. `headscale-bootstrap` oneshot seeds the SQLite DB with the `yggdrasil` user + reusable preauth-key (prefix+hash from sops). HuJSON policy lives inline (`policyFile`): default-allow ACL + `autoApprovers.exitNode` for `group:exit-approvers` (member `yggdrasil@`), so any node enrolled as `yggdrasil` that advertises `0.0.0.0/0` + `::/0` is approved without `headscale nodes approve-routes`.
- **`ddns.nix`** — systemd timer (every 10min) hitting `https://njal.la/update/` to refresh the A record for `headscale.valgrindr.net` with the host's public IP. Key from `sops.secrets."njalla-key-headscale"`.

## Exit node

Bifrost advertises as the yggdrasil exit-node via `hosts/optional/tailscale-exit-node.nix`:
- `services.tailscale.useRoutingFeatures = lib.mkForce "server"` enables IPv4/IPv6 forwarding sysctls.
- `tailscale-advertise-exit-node.service` (oneshot, `wantedBy = multi-user.target`) runs `tailscale set --advertise-exit-node=true` after `tailscaled` is up, so the flag is re-applied declaratively on every boot/deploy.
- Auto-approval is policy-driven from `headscale.nix`; no manual `approve-routes` needed.

Client opt-in is per-client and intentional. Outside on a hostile network:
```bash
tailscale set --exit-node=bifrost --exit-node-allow-lan-access=true
# back to direct:
tailscale set --exit-node=
```
Do not set as default anywhere: on the LAN it cripples throughput, off-LAN the ISP upload becomes the bottleneck.

## Bootstrap sequence (from-scratch install)

This host is brought up with `nixos-anywhere` from midgard, against a NixOS minimal installer running on the Proxmox VM. `hardware-configuration.nix` is committed (same Proxmox VM profile as asgard).

```bash
nix run github:nix-community/nixos-anywhere -- \
  -i ~/.ssh/lykill \
  --flake .#bifrost \
  --target-host root@<installer-ip>
```

After first boot:

1. Replace the placeholder `hosts/bifrost/ssh_host_ed25519_key.pub` with the real key:
   ```bash
   ssh sanfe@<bifrost-ip> 'sudo cat /persist/etc/ssh/ssh_host_ed25519_key.pub' \
     > hosts/bifrost/ssh_host_ed25519_key.pub
   ```
2. Derive the age recipient (`ssh-to-age < hosts/bifrost/ssh_host_ed25519_key.pub`) and add to `.sops.yaml` as `&bifrost`.
3. Add `*bifrost` to the key groups in `hosts/common/secrets.yaml` and `hosts/bifrost/secrets.yaml`; run `sops updatekeys` on both.
4. Redeploy. `tailscale-autoconnect-valgrindr.service` enrols bifrost into the yggdrasil tailnet automatically; `tailscale-advertise-exit-node.service` flags it as exit-node.

## Deploys

```bash
NIX_SSHOPTS="-i ~/.ssh/lykill" nixos-rebuild switch --flake .#bifrost \
  --target-host sanfe@192.168.1.55 --build-host sanfe@192.168.1.55 \
  --ask-sudo-password
```

Same `trusted-users`-off pattern as asgard: always build on the remote, never push pre-built closures.

## Caddy plugin pinning

The `caddy-dns/njalla` repo has no tagged releases. The plugin is pinned in `services/caddy.nix` to a Go pseudo-version `v0.0.0-YYYYMMDDHHMMSS-<short-sha>` plus a `sha256-…` hash. To bump:

1. Find the latest commit SHA on `github.com/caddy-dns/njalla`.
2. Replace both the timestamp and SHA in the pseudo-version (`v0.0.0-<ts>-<sha[:12]>`).
3. Set `hash = lib.fakeHash`, rebuild, capture the real hash from the nix error, paste it back.

## Recovery cheats

- **Wildcard cert fails to renew**: check `NJALLA_API_TOKEN` is in `/run/secrets/njalla-api-token` and the sops template `caddy-env` is mounted readable by `caddy`. Token rotation needs both the new value in sops and a Caddy restart.
- **`headscale.valgrindr.net` resolves to `127.0.0.1`**: the entry once existed in asgard's `/etc/hosts` and propagated via AdGuard's `/etc/hosts` resolution. Should no longer exist post-Phase-3; if it does, grep `networking.hosts` in `hosts/`.
- **Tailnet member can't resolve `*.lan.valgrindr.net`**: AdGuard isn't reachable. Check `nc -vz 192.168.1.55 53`; port 53 is opened explicitly in `dns.nix` (the AdGuard module's `openFirewall` only covers the webUI port).
