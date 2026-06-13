# modules/homelab

Reusable modules for native (non-container) NixOS app services, exposed under
the `homelab.services.<name>` option namespace. This is the native-service
counterpart to `modules/nixos/services/containers/*` — same "host just enables +
overrides" goal, for services that run as plain NixOS units rather than Podman
containers.

`default.nix` aggregates every module here; `flake.nix` merges it into
`outputs.nixosModules` (`(import ./modules/nixos) // (import ./modules/homelab)`),
so — like everything in `modules/nixos` — each module **auto-loads on every
host** and must be a no-op until its `enable` flag flips.

See `docs/services-reusable-modules-plan.md` for the rollout plan, rollout
phases, and the recorded design decisions (namespace, location, granularity).

## Authoring pattern

```nix
{ config, lib, ... }:
with lib; let
  cfg = config.homelab.services.myservice;
in {
  options.homelab.services.myservice = {
    enable = mkEnableOption "MyService";
    url = mkOption {            # FQDN for the local-Caddy vhost; null = no vhost
      type = types.nullOr types.str;
      default = null;
    };
    # … a few more knobs the host actually varies
  };

  config = mkIf cfg.enable {
    services.myservice = { enable = true; /* wire upstream from cfg */ };

    services.caddy.virtualHosts = mkIf (cfg.url != null) {
      ${cfg.url}.extraConfig = "reverse_proxy ${cfg.host}:${toString cfg.port}";
    };

    environment.persistence."${config.hostSpec.persistFolder}".directories = [ /* state */ ];
  };
}
```

Register it in `default.nix`:

```nix
{ myservice = import ./services/myservice; }
```

## Conventions

- **Thin wrapper, not fat.** Expose only the options a host realistically
  varies (`url`, data location, a couple of toggles). Wire the rest of the
  upstream `services.<thing>.*` inside the module. Users keep full access to
  `services.<thing>.*` for anything not surfaced — so don't re-expose every
  upstream knob (it rots when upstream renames options).
- **Default OFF.** Modules auto-load fleet-wide; every side-effect lives under
  `mkIf cfg.enable`. The options block itself must reference nothing
  host-specific (it's evaluated even when disabled).
- **The module owns ingress, persistence, and (when relevant) its sops
  secrets.** `url != null` ⇒ the module declares the `services.caddy.virtualHosts`
  entry itself (requires a Caddy on the host, e.g. `services.caddyNjalla.enable`).
  Persistence paths use `hostSpec.persistFolder`.
- **Fleet-generic only.** Host-specific quirks (storage backing, netns wiring,
  a one-host hack) stay in the host file. If a service only ever runs on one
  host and has no reuse story, leave it as a host-local file — wrapping it is
  overhead with no payoff.
- **Homepage tiles are NOT auto-added here (yet).** Homepage runs on bifrost
  while most services run on asgard — separate NixOS evaluations, so a module
  can't reach the homepage host's config. Cross-host tiles are a later phase
  (flake-level merging or a static fleet registry); see the plan doc.

## Current modules

- `services/immich/` — Immich photo/video library (the canary). `homelab.services.immich.{enable,url,host,port,mediaLocation,machineLearning}`. Owns the upstream `services.immich`, the local-Caddy vhost, and `/var/lib/immich` persistence. The pre-NAS `/mnt/nas/immich` tmpfiles backing stays in `hosts/asgard/services/immich.nix` (host-specific).
- `services/home-assistant/` — Home Assistant. `homelab.services.homeAssistant.{enable,url,port,name,extraConfig}`. Owns the behind-Caddy `http` block, the first-boot `!include`-target seeding + include-dir scaffolding, configDir persistence, and the vhost. `extraConfig` deep-merges (`recursiveUpdate`) over the baseline for host-specific config (e.g. asgard's mqtt broker, set in `hosts/asgard/services/home-automation/home-assistant.nix`). Mosquitto stays a separate host file — it's a distinct service, not part of the HA wrapper.
