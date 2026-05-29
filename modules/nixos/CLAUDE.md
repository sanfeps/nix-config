# modules/nixos

Reusable NixOS modules. Everything exported from `default.nix` is auto-imported into **every** host via `outputs.nixosModules` (see `hosts/common/core/base.nix`), so modules must be inert when their `enable` flag is off.

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

- `services/containers/` — Podman-backed service modules (`jellyfin` currently). Requires `hosts/optional/podman.nix` on the consuming host.

## Future direction

Container services are slated to migrate to `quadlet-nix` for rootless + pod support. Until then, container modules run as root systemd units via `virtualisation.oci-containers`. New container modules should still target the current API; the migration will rewrite all of them at once.
