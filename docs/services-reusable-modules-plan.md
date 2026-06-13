# Reusable service modules plan (stub)

> **Stub.** Goals + open decisions only. Full phasing waits until the per-host Caddy migration (`docs/per-host-caddy-migration-plan.md`) is done. At that point we'll have a real-world feel for the abstraction shape and can commit to the options interface.

## Goal

Migrate native NixOS app services from host-local files (`hosts/<host>/services/<name>.nix`) into reusable modules (`modules/homelab/services/<name>/default.nix` or similar) with a standardized options interface. Hosts then only enable + override:

```nix
homelab.services.immich = {
  enable = true;
  url = "immich.lan.valgrindr.net";
  mediaLocation = "/mnt/nas/immich";
};
```

This is what notthebee does for *every* service (not just containers). Today the repo already does this for containers via `modules/nixos/services/containers/*` — the plan extends the pattern to native NixOS services.

## Why this is a separate plan from the Caddy migration

- **Different risk shape.** Caddy migration is mechanical and per-service-reversible. Module refactor is a *design* problem — picking the right options surface needs evidence from at least one migrated service.
- **Avoids bloated commits.** Each Caddy-migration phase already touches bind address + vhost + DNS + firewall. Adding "and rewrite as a reusable module" would double the diff and muddy the bisect on regression.
- **The `services.caddyNjalla` shared module from Caddy-Phase-0 is the proof-of-concept.** If its option shape feels right after a few weeks in production, copy the pattern. If it feels off, we redesign before scaling out.

## Prerequisites

- Caddy migration Phases 0–5 landed and stable for ≥2 weeks.
- At least one service has been through a Caddy migration so we know what the post-migration native-service file looks like.

## Decisions to make before phasing

These are the design questions the stub deliberately leaves open. Each one wants a decision (recorded inline in this doc) before phase work begins.

### 1. Namespace

Three options:

- `homelab.services.<name>` (notthebee's choice). Pro: clear it's "ours", no risk of colliding with nixpkgs `services.*`. Con: invents a new top-level namespace.
- `services.apps.<name>`. Pro: stays inside the `services.*` tree, conceptually consistent. Con: nixpkgs may collide with `services.app*` in the future.
- Extend the existing `services.containers.<name>` pattern to native services too, e.g. `services.containers.<name>` → `services.selfhosted.<name>` (rename) or just keep `services.containers.*` for containers and add `services.native.*` for native services.

**DECIDED (2026-06-13): `homelab.services.*`.** Clearest "this is our abstraction" signal; zero collision risk with nixpkgs.

### 2. Module location

- `modules/homelab/services/<name>/default.nix` (notthebee). New top-level namespace under `modules/`.
- `modules/nixos/services/apps/<name>/default.nix` (extends existing tree). Less disruptive.

**DECIDED (2026-06-13): `modules/homelab/services/<name>/default.nix`.** Wired into `outputs.nixosModules` in `flake.nix` via `(import ./modules/nixos) // (import ./modules/homelab)`, so homelab modules auto-load on every host exactly like `modules/nixos/*`. `modules/homelab/default.nix` is the aggregator.

### 3. Option granularity

How much should the module abstract?

- **Thin wrapper**: just `enable`, `url`, maybe `port`. Module sets the corresponding `services.<thing>.*` options; users can still override the native options directly.
- **Fat wrapper**: every relevant native option re-exposed as an option (`cfg.dataDir`, `cfg.adminEmail`, `cfg.smtpHost`, …). Users never touch `services.<thing>.*` directly.

Notthebee leans thin. Recommendation: **thin**, because over-abstracting kills the ability to use upstream NixOS docs and adds maintenance burden every time upstream changes options.

### 4. Caddy integration as an option

Two shapes:

- Each module just sets `services.caddy.virtualHosts.<cfg.url>` directly when `cfg.enable && cfg.url != null`. Done.
- Introduce a sub-option like `cfg.expose = { url = …; auth = false; trustedProxy = null; };` and have the module render the Caddy block from that. Reusable when Authentik lands (just flip `auth = true`).

**Recommendation: start with the first (just set virtualHosts), introduce `cfg.expose` only when Authentik lands and forward-auth becomes the third repeating thing.** Don't pre-abstract.

### 5. Sops integration

Should the module declare its sops secret paths?

- **Yes**: module declares `sops.secrets."immich/postgres-password" = {…};` and reads `config.sops.secrets.…path`. Host doesn't write any sops boilerplate.
- **No**: host declares secrets, passes paths into the module via options.

**Recommendation: yes**, conditional on `cfg.enable`. The convention is already "secret name = service name + role", so the module owns the path and the host owns the value.

### 6. Persistence

Declare inside the module (`environment.persistence."/persist".directories += [{ directory = cfg.dataDir; … }]`) or leave to host?

**Recommendation: declare inside the module.** Persistence directories are 1:1 with the service's state — leaking that into the host file just spreads the contract.

### 7. Homepage tile

Auto-add a tile to the homepage when the service enables?

- **Yes**: module appends to `services.homepage-dashboard.settings.services` (when homepage is enabled on the same fleet). Conventional grouping by service category.
- **No**: tiles stay declared in `hosts/bifrost/services/homepage.nix`.

**Recommendation: defer.** Auto-tile is nice but the homepage runs on a different host than most services; gathering tiles cross-host needs evaluating either via flake-level option merging or a sops-style "tile registry" file. Tackle as a Phase 2 of this plan once the basic module shape works.

### 8. Host-specific quirks — how does the module accommodate them?

Edge cases that don't fit a clean option:

- **Mullvad netns** (sonarr/radarr/prowlarr/qbittorrent). The netns wiring is asgard-specific. Option: `cfg.netns = "mullvad";` that the module honors only if the netns exists, otherwise opt-out.
- **Shared Postgres** (Firefly + Ghostfolio share `127.0.0.1:5432`). Option: `cfg.postgres.shared = true;` that defers DB creation to a separate `services.containers.postgres` (or whatever it ends up called) module.
- **PHP-FPM Unix socket** (Firefly). Already self-contained inside the module — no host knowledge needed once Caddy migration lands.

**Recommendation: defer until the canary migration hits one of these.** Premature options for hypothetical edge cases is exactly the trap.

## Out of scope (intentionally)

- Container modules under `modules/nixos/services/containers/*` already follow this pattern. Don't rewrite them. The plan is about reaching parity for native services.
- Modules for desktop / home-manager features (`home/sanfe/features/*`). Those are a separate abstraction concern.
- The `caddyNjalla` shared module from Caddy-Phase-0. Already in the new pattern.

## Open questions

1. **Should we adopt `homelab.*` as the umbrella namespace for everything that's "our convention" (not nixpkgs upstream)?** E.g. `homelab.services.*`, `homelab.persistence.*`, `homelab.sops.*`. Bigger commitment but cleaner.
2. **Cross-host visibility**: if a tile on bifrost's homepage wants to know about a service on asgard, does it use flake-level merging (`outputs.nixosConfigurations.asgard.config.homelab.services.…`) or a static registry file? The first is "correct" but harder to read. The second is brittle.
3. **Does `services.caddyNjalla` get folded into `homelab.networking.tls` or stay where it is?** Probably stay — it's not a service, it's infrastructure. But worth deciding.

## Phasing (placeholder)

To be written after Caddy-Phase-5 lands. Rough shape:

- **Phase A**: Pick canary (likely Immich or Ghostfolio — both already have a clean shape after Caddy migration). Design the options interface for it specifically. Build `modules/homelab/services/<canary>/default.nix`. Refactor the host file to just enable + override.
- **Phase B**: Migrate one quirk-free service to validate the pattern (Home Assistant or Immich, whichever wasn't the canary).
- **Phase C**: Migrate the quirky ones — Firefly (PHP-FPM specifics), shared Postgres, media stack (Mullvad netns).
- **Phase D**: Pick up the cross-host concerns (homepage tile registry, sops convention codification).
- **Phase E**: CLAUDE.md sweep — root, both hosts, `modules/nixos/CLAUDE.md`.

## Risks

- **Over-abstraction.** The temptation to wrap every NixOS option is real; resist it. If a service has 3 reasonable knobs, expose 3. If it has 30, expose 3 and let users drop into `services.<thing>.*` for the rest.
- **Naming churn.** Picking the namespace late means renaming a bunch of services later. Decide once, in the first phase.
- **Hiding upstream NixOS option changes.** When nixpkgs renames or deprecates an option, the wrapper module needs to track it. Stick to thin wrappers to minimize this.
- **Solo abstraction.** If a service only ever runs on one host, wrapping it as a reusable module is overhead with no payoff. Apply the pattern only to services where reuse is plausible (Immich, Jellyfin, media stack, Vaultwarden, etc — yes; Firefly is borderline if it only ever runs on asgard).
