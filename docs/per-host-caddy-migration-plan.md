# Per-host Caddy migration plan

## Goal

Move from the current **DMZ-edge** model (single Caddy on bifrost, asgard apps reverse-proxied across hosts via firewall holes) to a **per-host ingress** model (each app-running host runs its own Caddy with its own LE wildcard cert; service modules declare their own `services.caddy.virtualHosts.…` inline; bifrost no longer fronts asgard services).

Rationale: scale to 3+ app hosts without N-times-the-firewall-rules per service, eliminate the bifrost-as-SPOF-for-apps risk, give each new host a self-contained service contract, align with the notthebee fleet pattern in anticipation of growth.

## Decisions baked into this plan

1. **Per-host wildcard cert via Njalla DNS-01.** Each Caddy renews `*.lan.valgrindr.net` independently. No cert sharing/rsync. Cost: two ACME orders per ~60 days instead of one. Benefit: zero cross-host coupling. The Njalla API token is already in `hosts/common/secrets.yaml`, so adding asgard as a recipient is a no-op (it already is).
2. **Per-service inline vhost.** Each service module declares its own `services.caddy.virtualHosts."${cfg.url}".extraConfig`. No central per-host `caddy.nix` aggregator. Service ownership stays self-contained — adding/removing a service touches one file.
3. **Caddy+Njalla bundle as a shared module.** `modules/nixos/services/caddy-njalla.nix` exposes `services.caddyNjalla.enable = true` and bundles: the `pkgs.caddy.withPlugins` build, the sops template for the API-token env file, the global `acme_dns njalla` directive, persistence for `/var/lib/caddy`, and firewall ports 80/443. Per-host opt-in is one line.
4. **DNS rewrites updated, not abandoned.** AdGuard stays on bifrost. Per-service rewrites change destination (asgard services → `192.168.1.54`, bifrost services → `192.168.1.55`) but the names don't change.
5. **The `services.lan.expose` plan is dropped.** Its problem (firewall hole + Caddy handle + DNS rewrite triplet) goes away in this model — there's no firewall hole, no cross-host Caddy handle. Only the DNS rewrite remains, which is a 2-line block already. Delete `docs/lan-expose-module-plan.md` at the end of Phase 5.

## Target architecture

After migration:

- **bifrost Caddy** terminates TLS only for **bifrost-local** services: `headscale.valgrindr.net` (public), `adguard.lan.valgrindr.net`, `homepage.lan.valgrindr.net`, `headplane.lan.valgrindr.net`. Fallback `404` stays.
- **asgard Caddy** terminates TLS for **asgard-local** services: `firefly`, `ghostfolio`, `home`, `immich`, plus the media stack (`jellyfin`, `seerr`, `qbittorrent`, `prowlarr`, `sonarr`, `radarr`) once that lands.
- **Firewall**: asgard opens `:80`/`:443` to the LAN. All the bifrost-only firewall holes (Ghostfolio 3333, Home Assistant 8123, Immich 2283, Firefly 80) collapse: those services now listen on `127.0.0.1` only, fronted by local Caddy.
- **AdGuard rewrites**: asgard services rewritten to `192.168.1.54`; bifrost services stay on `192.168.1.55`.
- **The cross-host Firefly hack disappears.** Caddy on asgard talks directly to PHP-FPM's Unix socket and terminates TLS itself. No more "lie to PHP with `env HTTPS on`" workaround.

## Pre-flight checks

- [ ] Verify asgard is already an age recipient for the Njalla API token: `grep -A5 njalla-api-token hosts/common/secrets.yaml` should decrypt cleanly on asgard (`ssh asgard 'sops -d /var/lib/.../path'`). It already is — `hosts/common/secrets.yaml` is encrypted to all hosts.
- [ ] Confirm there's no LE rate-limit concern: per-host wildcards mean two issuances of the same SAN within ~60 days. LE's "duplicate certificate" limit is 5/week per identical SAN set — we're well under.
- [ ] Confirm router still port-forwards `80`/`443` to bifrost only — public ingress for `headscale.valgrindr.net` remains bifrost's job. Nothing on asgard should be reachable from the internet.

## Phases

### Phase 0 — Factor Caddy+Njalla into a shared module

**Touches**: `modules/nixos/services/caddy-njalla.nix` (new), `modules/nixos/default.nix`, `hosts/bifrost/services/caddy.nix`.

1. Create `modules/nixos/services/caddy-njalla.nix` exposing `services.caddyNjalla.enable`. The module owns:
   - The pinned plugin version + hash (currently lives in `hosts/bifrost/services/caddy.nix:9-14`).
   - `services.caddy.enable = true` + `services.caddy.package = caddyWithNjalla`.
   - `sops.secrets."njalla-api-token"` + `sops.templates."caddy-env"` (env file).
   - `services.caddy.environmentFile = …caddy-env.path`.
   - `services.caddy.globalConfig = "acme_dns njalla {env.NJALLA_API_TOKEN}";`.
   - `networking.firewall.allowedTCPPorts = [80 443]`.
   - `environment.persistence."/persist".directories` for `/var/lib/caddy`.
2. Export in `modules/nixos/default.nix`.
3. Rewrite `hosts/bifrost/services/caddy.nix` to enable the new module and only declare `virtualHosts.*` (no daemon/package wiring). Behaviour is unchanged.
4. `nix flake check` + deploy bifrost. Validate every vhost still resolves and serves correctly.

**Exit criterion**: bifrost behaves identically; the file is shorter and reusable.

### Phase 1 — Canary: Immich on asgard's own Caddy

**Touches**: `hosts/asgard/services/caddy.nix` (extend), `hosts/asgard/services/immich.nix` (inline vhost), `hosts/bifrost/services/caddy.nix` (remove Immich handle), `hosts/bifrost/services/dns.nix` (update rewrite).

Why Immich first: simplest backend (single port, plain HTTP, no `X-Forwarded-For` pitfalls), self-contained, and the easiest to roll back.

1. On asgard, replace the Firefly-only `caddy.nix` stub with `services.caddyNjalla.enable = true` (from Phase 0).
2. Drop the existing `iptables -I nixos-fw -p tcp --dport 80 -s 192.168.1.55` hack — asgard now listens on `:80`/`:443` to the LAN. Keep the firewall closed on backend ports.
3. In `hosts/asgard/services/immich.nix`, add an inline vhost:
   ```nix
   services.caddy.virtualHosts."immich.lan.valgrindr.net".extraConfig = ''
     reverse_proxy 127.0.0.1:2283
   '';
   ```
   Rebind Immich to `127.0.0.1:2283` in the same edit.
4. Remove the `iptables -I nixos-fw -p tcp --dport 2283 -s 192.168.1.55` rule for Immich.
5. On bifrost, delete the `@immich` handle in `caddy.nix` and update the AdGuard rewrite for `immich.lan.valgrindr.net` from `192.168.1.55` to `192.168.1.54` in `dns.nix`.
6. Deploy **asgard first** (so the new endpoint exists before DNS swings), then bifrost.
7. Validate: `https://immich.lan.valgrindr.net` works from a LAN client and from a tailnet client. Cert is asgard-issued (check the chain).

**Rollback**: revert the AdGuard rewrite, re-add the bifrost handle, redeploy bifrost. Asgard's extra Caddy doesn't have to come back down; Immich just gets two paths to it temporarily.

**Exit criterion**: Immich runs end-to-end without going through bifrost. asgard is now issuing its own LE wildcard cert.

### Phase 2 — Migrate Ghostfolio & Home Assistant

Same shape as Phase 1, one at a time, validate end-to-end before the next.

**Ghostfolio** (`hosts/asgard/services/finances/ghostfolio.nix`):
- Inline vhost → `reverse_proxy 127.0.0.1:3333`.
- Rebind container to `127.0.0.1:3333` (it currently listens on `0.0.0.0:3333`).
- Drop firewall hole for 3333.
- Bifrost: delete handle + flip rewrite.

**Home Assistant** (`hosts/asgard/services/home-automation/…`):
- Inline vhost → `reverse_proxy 127.0.0.1:8123`.
- Rebind to `127.0.0.1:8123`.
- Drop firewall hole for 8123.
- `trusted_proxies` in Home Assistant changes from `192.168.1.55` to `127.0.0.1` (Caddy is now local).
- Bifrost: delete handle + flip rewrite.

### Phase 3 — Migrate Firefly (the special case)

**Touches**: `hosts/asgard/services/finances/firefly.nix`, asgard `caddy.nix` (collapse the stub).

The cross-host Firefly hack (`env HTTPS on`, `env SERVER_PORT 443`) was only needed because TLS was terminated on bifrost. Now asgard Caddy terminates TLS itself, so PHP sees the real `https://` request.

1. Inline vhost in `firefly.nix`:
   ```nix
   services.caddy.virtualHosts."firefly.lan.valgrindr.net".extraConfig = ''
     root * ${config.services.firefly-iii.dataDir}/public
     php_fastcgi unix/${config.services.phpfpm.pools.firefly.socket.path}
     file_server
   '';
   ```
   No more `env HTTPS on` / `env SERVER_PORT 443` lies.
2. Delete the asgard `services/caddy.nix` stub — it's now empty.
3. Bifrost: delete the `@firefly` handle, flip the AdGuard rewrite.

### Phase 4 — Migrate the media stack & dissolve `media-proxies.nix`

**Touches**: each `hosts/asgard/services/media/{jellyfin,seerr,qbittorrent,prowlarr,sonarr,radarr}.nix` to add its own inline vhost; delete `hosts/bifrost/services/media-proxies.nix`.

The current `media-proxies.nix` on bifrost is six handles in one file — pure scaffold mode until the Mullvad netns lands. Easier to migrate while the media stack is still inactive: convert the bifrost handles into inline vhosts on the asgard service modules, delete `media-proxies.nix`, drop the import. When the media stack activates, the ingress is already in place.

For the Mullvad-netns services (sonarr/radarr/prowlarr/qbittorrent): Caddy lives in the main netns, the apps live in the Mullvad netns. The Caddy `reverse_proxy` target uses the netns'd app's veth IP (the same way the current `media-proxies.nix` works). No protocol changes needed.

### Phase 5 — Shrink bifrost Caddy & retire the LAN-expose plan

**Touches**: `hosts/bifrost/services/caddy.nix`, `docs/lan-expose-module-plan.md` (delete).

After Phases 1–4, bifrost's `caddy.nix` looks like:

```nix
virtualHosts."headscale.valgrindr.net".extraConfig = ''
  reverse_proxy 127.0.0.1:8080
'';

virtualHosts."*.lan.valgrindr.net".extraConfig = ''
  @adguard host adguard.lan.valgrindr.net
  handle @adguard {
    reverse_proxy 127.0.0.1:3000
  }
  # headplane + homepage handles still live in their own modules
  handle {
    respond "bifrost edge - unknown subdomain" 404
  }
'';
```

Also: `services.lan.expose` no longer makes sense — the triplet it was meant to collapse only exists in the old model. Delete `docs/lan-expose-module-plan.md` and remove the corresponding memory entry.

### Phase 6 — Update Authentik plan (forward-looking)

This is forward-looking, not part of the migration itself. The current `docs/authentik-implementation-plan.md` assumes a single Caddy on bifrost handling forward-auth for the fleet. With per-host Caddy:

- **Authentik server** lives on asgard (now-default Pattern A). It's an app, not networking infra.
- **Forward-auth** is configured on each Caddy that fronts a protected app. The Caddy snippet (`forward_auth authentik.lan.valgrindr.net:9000 { uri /outpost.goauthentik.io/auth/caddy … }`) gets templated as a reusable snippet in a shared Nix module, opt-in per vhost.
- **Outpost reachability**: Caddy on asgard talks to Authentik on `127.0.0.1`; Caddy on bifrost talks to Authentik at `192.168.1.54:9000` (firewall hole back, but only for Authentik — small surface).

Update `docs/authentik-implementation-plan.md` in the same commit as Phase 6.

## CLAUDE.md updates

To be edited at the end of each relevant phase, not all up front (so docs and code don't desync):

### Root `CLAUDE.md`

**Phase 0**:
- Add a note under "Modular Host Configuration" about the new `services.caddyNjalla` shared module.

**Phase 1** (first time the new pattern lands):
- Rewrite "Adding a new networked service" entirely. New shape:
  - **Single pattern**: define the service in `hosts/<host>/services/<group>/<name>.nix`, bind it to `127.0.0.1`, declare `services.caddy.virtualHosts."${name}.lan.valgrindr.net".extraConfig` inline in the same module, add the AdGuard rewrite on bifrost pointing at that host. Done.
  - Drop the firewall-rule step entirely.
  - Drop the `X-Forwarded-For` trusted-proxy step in the common case (Caddy is on `127.0.0.1` for the backend now).
- Update "Active Hosts" → bifrost: stop describing it as the LAN ingress for asgard apps; describe it as "edge for networking infra (DNS, headscale, public TLS for headscale.valgrindr.net) and its own apps".

**Phase 5**:
- Remove the references to Pattern A/B framing if anything still hangs on. Just one pattern remains.

### `hosts/asgard/CLAUDE.md`

**Phase 1**:
- Rewrite the **Caddy** section. New shape: "asgard runs Caddy via the shared `caddyNjalla` module with its own wildcard LE cert via Njalla DNS-01. Each service module declares its own `virtualHosts` block inline. Asgard listens on `:80`/`:443` to the LAN."
- Update each service line (Firefly, Ghostfolio, Home Assistant, Immich) to say "fronted by local Caddy" instead of "Caddy on bifrost reverse-proxies…".
- Drop the "Recovery cheats → 502 on a vhost" line referencing bifrost; replace with "check `systemctl status caddy` on asgard".
- Drop the "Phase-3-cutover" history line (still accurate but stale framing).

### `hosts/bifrost/CLAUDE.md`

**Phase 5**:
- Rewrite the role line: "bifrost is the LAN's networking edge (DNS, headscale, public TLS for headscale.valgrindr.net) and its own apps. It no longer fronts asgard."
- Rewrite the **Services → caddy.nix** bullet: drop the Ghostfolio/Home Assistant/Firefly/Immich/media-proxies references; keep AdGuard/Homepage/Headplane/public headscale.
- Delete the **`media-proxies.nix`** bullet entirely (the file is gone).
- Update the **Recovery cheats** that talk about "vhost is on bifrost"; clarify which vhosts live where.

### `modules/nixos/CLAUDE.md`

**Phase 0**:
- Add a section describing `services.caddyNjalla` as the reusable Caddy+Njalla bundle.

## Rollback strategy

Each phase is independently revertible:

- **Phase 0**: the shared module is additive; reverting just inlines the config back into bifrost's caddy.nix.
- **Phases 1–4 (per-service)**: revert the service-module patch (re-binds to `0.0.0.0`, deletes the inline vhost), re-add the bifrost handle, flip the AdGuard rewrite back to `192.168.1.55`, re-add the firewall hole. Deploy bifrost first this time (so the proxy path is back before the listener moves back to `0.0.0.0`).
- **Phase 5**: re-add the deleted handles. Trivial.

Don't deploy more than one service migration per session — validate each end-to-end (LAN browser, tailnet client, cert chain) before moving to the next.

## Open questions

1. **Per-host wildcard TXT collisions on Njalla?** Both Caddys issue for the same SAN at different times. Caddy handles `_acme-challenge.lan.valgrindr.net` TXT records via the Njalla plugin; concurrent issuance is unlikely (renewals are staggered) but worth watching the first time both certs come up for renewal in the same week.
2. **Homepage tile destinations** stay the same (the public URL doesn't change), but worth a manual pass after Phase 5 to make sure nothing references `bifrost`-as-edge in tile docs/descriptions.
3. **Backups for `/var/lib/caddy`**: each Caddy now persists its own ACME state. Existing `environment.persistence."/persist".directories` already covers `/var/lib/caddy` on bifrost; the shared module copies that declaration to asgard.

## Order of operations summary

```
Phase 0:  refactor module                  → deploy bifrost
Phase 1:  Immich on asgard Caddy           → deploy asgard, then bifrost
Phase 2:  Ghostfolio                       → deploy asgard, then bifrost
          Home Assistant                   → deploy asgard, then bifrost
Phase 3:  Firefly                          → deploy asgard, then bifrost
Phase 4:  Media stack vhosts (scaffold)    → deploy asgard, then bifrost
Phase 5:  shrink bifrost Caddy             → deploy bifrost; delete lan-expose plan
Phase 6:  re-scope Authentik plan          → doc-only
```

End state: every app on asgard fronted by asgard's own Caddy + cert; bifrost is purely networking-edge + its own infra UIs; new app hosts only need to import `services.caddyNjalla` and start declaring vhosts.
