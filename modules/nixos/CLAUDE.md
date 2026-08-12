# modules/nixos

Reusable NixOS modules. Everything exported from `default.nix` is auto-imported into **every** host via `outputs.nixosModules` (see `hosts/common/core/base.nix`), so modules must be inert when their `enable` flag is off.

> Native (non-container) app services live in the sibling tree `modules/homelab/` under the `homelab.services.*` namespace (merged into `outputs.nixosModules` in `flake.nix`). Use that for plain NixOS-unit services; use this tree for container services and shared infrastructure. See `modules/homelab/CLAUDE.md`.

## Authoring pattern

Each module follows:

```nix
{ config, lib, pkgs, ... }:
with lib; let
  cfg = config.services.containers.myservice;
in {
  options.services.containers.myservice = {
    enable = mkEnableOption "MyService";
    # … other options
  };

  config = mkIf cfg.enable {
    # everything goes under mkIf so the module is a no-op until enabled
  };
}
```

Then register it in `default.nix`:

```nix
{
  myservice = import ./services/containers/myservice.nix;
}
```

Hosts that want it set `services.containers.myservice.enable = true` in their own config.

## Conventions

- **Default OFF.** Modules auto-load on every host, so `enable` must default to `false` (`mkEnableOption` does this) and every config side-effect must live under `mkIf cfg.enable`.
- **Persistence paths use `hostSpec.persistFolder`** so the module slots into impermanence without extra wiring.
- **`openFirewall` is the user's choice.** Default `false`; let the host opt in.
- **Assertions over silent failures.** If the module needs an external prerequisite (e.g. `virtualisation.oci-containers.backend == "podman"`), assert it explicitly with a clear message — see `services/containers/jellyfin.nix` for the pattern.
- **No host-specific defaults.** A module here should be reusable across hosts; if it only makes sense on one host, put it under `hosts/<host>/` instead.

## Current layout

- `services/containers/` — Podman-backed service modules (`ghostfolio`, `headplane`, `yamtrack`). Requires `hosts/optional/podman.nix` on the consuming host. `ghostfolio` showcases the env-file pattern: secrets enter via `environmentFile` (a path rendered by `sops.templates`) so the module itself stays secrets-free. `yamtrack` follows the same pattern and adds two things worth copying: a `port` option whose description documents that the upstream image **cannot** be bound to loopback (so the firewall is the privacy boundary), and an `exportDir` bind-mount that keeps the backup path out of container internals.
- `services/caddy-njalla.nix` — Caddy + Njalla DNS-01 plugin bundle. Owns the plugin version+hash pin, the `njalla-api-token` sops secret and `caddy-env` sops template, the `acme_dns njalla` global config, ports 80/443, and `/var/lib/caddy` persistence. Hosts opt in with `services.caddyNjalla.enable = true` and then declare their own `services.caddy.virtualHosts.*` separately. This is the per-host-ingress building block — every host that fronts apps with its own LE wildcard cert enables it.

## Container image pinning (required)

**Never default a container `image` to `:latest`.** Pin `version@digest`:

```nix
default = "ghcr.io/fuzzygrim/yamtrack:0.26.1@sha256:2c4c8ef…";
```

`:latest` is the worst of both worlds here, because of how the generated unit behaves: the pre-start script only does `podman rm -f <name>`, and `ExecStart`'s `podman run` uses podman's default pull policy **`missing`** — it pulls *only if the image is absent locally*. There is no auto-update timer (the only podman timer is `podman-prune`). So a `:latest` image is fetched **once, on first start, and then never again**:

- **not reproducible** — the config records nothing about what is actually running, and a from-scratch rebuild pulls whatever `latest` means that day;
- **not current** — it silently freezes. Measured 2026-08-12: asgard was running Ghostfolio **3.34.0** while upstream was on **3.49.0**.

The `version@digest` form fixes both: the tag makes an upgrade legible in `git log` (`3.34.0 → 3.49.0`), the digest makes it immutable (tags can be re-pushed). Byparr (`hosts/asgard/services/media/byparr.nix`) already pinned by bare digest — that is immutable but unreadable; prefer `version@digest` for new pins.

**To upgrade an image:**

```bash
skopeo inspect --format '{{.Digest}}' docker://<image>:<new-version>
```

Update both halves in the same commit, deploy, verify. Podman pulls the new digest because it is not present locally.

> Upgrades are now **explicit**. That is the point — e.g. a Yamtrack bump can invalidate its Redis cache version and silently reintroduce the webhook 500s (see `hosts/asgard/CLAUDE.md`), and Headplane 0.6.3 is the version bifrost's cookie-secret workaround targets.

## Future direction

Container services are slated to migrate to `quadlet-nix` for rootless + pod support. Until then, container modules run as root systemd units via `virtualisation.oci-containers`. New container modules should still target the current API; the migration will rewrite all of them at once.
