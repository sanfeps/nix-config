# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Documentation Layout

Context lives in nested `CLAUDE.md` files. Claude Code auto-loads the root file plus any `CLAUDE.md` along the path of the files being touched, so per-area notes stay close to the code they describe:

- `CLAUDE.md` (this file): cross-cutting conventions (commits, sops, headscale, DNS, deploys) and the new-service checklist.
- `hosts/asgard/CLAUDE.md`: asgard-specific topology (app server), services on the box, known gotchas.
- `hosts/bifrost/CLAUDE.md`: bifrost-specific topology (networking edge), services, recovery cheats.
- `hosts/common/core/CLAUDE.md`: what each core module owns and the load order assumptions.
- `modules/nixos/CLAUDE.md`: pattern for authoring reusable NixOS modules in this repo.

**When you make a change that invalidates or extends what these files say, update the relevant `CLAUDE.md` in the same commit.** If a directory grows new architectural weight and doesn't yet have a `CLAUDE.md`, create one. Treat documentation drift as a bug.

## Overview

This is a personal NixOS configuration repository using a flake-based setup with home-manager integration. The workstation (midgard) uses wipe-on-boot impermanence with BTRFS + LUKS; the Proxmox-VM app servers (asgard, bifrost) use plain BTRFS subvolumes with `/persist` as a convention but no rootfs wipe.

## Build and Deployment Commands

### NixOS System Operations

```bash
# Build and activate system configuration for current host
sudo nixos-rebuild switch --flake .

# Build and activate for specific host
sudo nixos-rebuild switch --flake .#midgard
sudo nixos-rebuild switch --flake .#asgard

# Test configuration without setting default boot entry
sudo nixos-rebuild test --flake .

# Build configuration without activating
sudo nixos-rebuild build --flake .

# Check configuration for syntax errors
nix flake check
```

### Home Manager Operations

Home-manager is NixOS-integrated on most hosts (midgard), so it gets activated as part of `nixos-rebuild switch`. Standalone home-manager only exists for hosts where the user lives without root (currently only `sanfe@asgard`):

```bash
# Standalone home-manager (only sanfe@asgard is exposed)
home-manager switch --flake .#sanfe@asgard
```

### Remote Deploys

`asgard` is a Proxmox VM on the LAN. Deploys are driven from a workstation (midgard) using `--target-host` and `--build-host` together — both point at the remote so the closure is built on asgard and never pulled through the workstation:

```bash
NIX_SSHOPTS="-i ~/.ssh/lykill" nixos-rebuild switch --flake .#asgard \
  --target-host sanfe@192.168.1.54 \
  --build-host  sanfe@192.168.1.54 \
  --ask-sudo-password
```

`trusted-users` is intentionally NOT set on the workstation (rejected for security): always rely on `--build-host` instead of pushing pre-built closures.

### Code Formatting

```bash
# Format all Nix files using alejandra
nix fmt

# Check flake outputs
nix flake show
```

### Development Shell

```bash
# Enter development shell with SOPS and age tools
nix develop

# Or use direnv if configured
direnv allow
```

## Architecture

### Repository Structure

- **flake.nix**: Main entry point defining all inputs, outputs, and system/home configurations
- **hosts/**: Per-host NixOS system configurations
  - **hosts/common/core/**: Shared base configuration for all hosts (locale, nix settings, ssh, sops, persistence)
  - **hosts/common/disks/**: Reusable disk layout configurations (BTRFS, LUKS, impermanence variants)
  - **hosts/common/users/**: User account definitions
  - **hosts/optional/**: Optional system features (display managers, wireless, desktop environments)
  - **hosts/{hostname}/**: Individual host configurations (e.g., midgard, asgard)
- **home/**: Home-manager configurations per user
  - **home/sanfe/common/core/**: Shared home-manager base configuration
  - **home/sanfe/features/**: Modular home configuration features (desktop, games, etc.)
  - **home/sanfe/{hostname}.nix**: Per-host home-manager entry points
- **modules/**: Custom NixOS and home-manager modules
  - **modules/common/**: Shared module definitions (e.g., host-spec)
  - **modules/nixos/**: Custom NixOS modules
  - **modules/home-manager/**: Custom home-manager modules (fonts, monitors)
- **pkgs/**: Custom package definitions
- **overlays/**: Nixpkgs overlays for package modifications
- **hydra.nix**: Hydra CI job definitions for building packages and system configurations

### Key Architectural Patterns

#### Impermanence Strategy
The `/persist` root is a project-wide convention, but **wipe-on-boot impermanence is per-host** and gated by which disk layout the host imports from `hosts/common/disks/`:

- **`btrfs-luks-impermanence-disk.nix`** — wipes `/` on every boot via `boot.initrd.postDeviceCommands` (`btrfs subvolume delete` of the root subvol, then re-create). The root filesystem is genuinely ephemeral. Currently used by **midgard** only.
- **`btrfs-disk-uefi.nix`** — plain BTRFS subvolumes (`/`, `/nix`, `/persist`), no wipe logic. Used by the Proxmox VMs (**asgard**, **bifrost**). The `/persist` convention is followed for documentation/portability — `environment.persistence."/persist"` declarations and `hosts/common/core/optin-persistence.nix` still work — but bind-mounting persistent state onto a persistent rootfs is a no-op. Anything written to `/var/lib/<svc>` survives reboots regardless of whether it's declared in `environment.persistence`.

When porting state-handling notes between hosts, check the disk layout first: hacks needed on midgard (e.g. `DynamicUser`'s `/var/lib/private` collision with bind-mounts) are non-issues on asgard/bifrost.

Persistence configuration:
- NixOS: `hosts/common/core/optin-persistence.nix`
- Home-manager: `home/sanfe/common/core/default.nix` (persistence block)

#### Modular Host Configuration
Each host imports from three categories:
1. **Hardware**: Hardware-specific config and nixos-hardware modules
2. **Disk Layout**: Imported from `hosts/common/disks/` with disko
3. **Core + Optional**: Base system (`hosts/common/core`) plus optional features (`hosts/optional/`)

#### Home-Manager Integration
Home-manager is integrated at the NixOS level through `inputs.home-manager.nixosModules.home-manager` in core configuration. Each user has per-host home-manager configurations in `home/sanfe/{hostname}.nix`.

#### Secrets Management
Secrets are managed with sops-nix using age encryption. The development shell automatically sets `SOPS_AGE_KEY_FILE` to `~/.config/sops/age/keys.txt`. Secrets are defined in `hosts/common/secrets.yaml`.

#### Flake Inputs
Key dependencies:
- **nixpkgs**: Main package source (unstable channel)
- **nixpkgs-stable**: Stable channel for select packages (24.11)
- **home-manager**: User environment management
- **impermanence**: Ephemeral root filesystem support
- **sops-nix**: Secret management
- **disko**: Declarative disk partitioning
- **hardware**: nixos-hardware device-specific configurations
- **quickshell**: Custom shell integration

#### Special Args Flow
- `inputs` and `outputs` are passed as `specialArgs` to both NixOS and home-manager configurations
- All custom overlays from `overlays/` are automatically applied
- All custom modules from `modules/nixos/` and `modules/home-manager/` are automatically imported

#### Host Specification Module
The `hostSpec` module (`modules/common/host-spec.nix`) provides standardized options for differentiating hosts:
- `username`: Primary user account
- `email`: User email addresses
- `domain`: Host domain
- `persistFolder`: Persistence root directory (default: `/persist`)

Set in each host's core configuration and accessible throughout the system.

#### Monitor Configuration
Home-manager supports a custom `monitors` option for declarative multi-monitor setup. Defined per-host in `home/sanfe/{hostname}.nix` with properties: name, width, height, workspace, primary.

#### Caddy Edge Module
`modules/nixos/services/caddy-njalla.nix` bundles the Caddy daemon, the `caddy-dns/njalla` plugin (pinned via `pkgs.caddy.withPlugins`), the `njalla-api-token` sops secret + `caddy-env` sops template, the `acme_dns njalla` global config, ports 80/443, and `/var/lib/caddy` persistence into a single opt-in: `services.caddyNjalla.enable = true`. Hosts that front apps with their own wildcard LE cert enable it and then declare `services.caddy.virtualHosts.*` separately. This is the per-host ingress building block — see `docs/per-host-caddy-migration-plan.md` for the migration away from the bifrost-as-DMZ model.

#### Reusable Service Modules (`homelab.services.*`)
Native (non-container) NixOS app services are being migrated from host-local files into reusable modules under `modules/homelab/services/<name>/default.nix`, exposed under the `homelab.services.<name>` option namespace. `modules/homelab/default.nix` aggregates them and `flake.nix` merges that tree into `outputs.nixosModules` (`(import ./modules/nixos) // (import ./modules/homelab)`), so — exactly like `modules/nixos/*` — every entry auto-loads on every host and must stay inert until its `enable` flag flips. A host then only enables + overrides, e.g.:

```nix
homelab.services.immich = {
  enable = true;
  url = "immich.lan.valgrindr.net";
  mediaLocation = "/mnt/nas/immich";
};
```

These are **thin wrappers**: expose the few knobs a host varies, wire the rest (the upstream `services.<thing>.*`, the local-Caddy vhost, persistence) inside the module, and let users drop into `services.<thing>.*` directly for anything not surfaced. Host-specific quirks (e.g. asgard's pre-NAS tmpfiles backing for Immich) stay in the host file. Immich is the canary; see `modules/homelab/CLAUDE.md` for the authoring pattern and `docs/services-reusable-modules-plan.md` for the rollout plan and recorded design decisions.

#### Container Services
Declarative Podman container services are managed through custom NixOS modules located in `modules/nixos/services/containers/`. Each service module defines options and configuration for running containers via `virtualisation.oci-containers`.

**Base Configuration**: `hosts/optional/podman.nix` provides Podman with Docker compatibility, DNS-enabled networking, docker socket for rootless support, and management tools (podman-compose, podman-tui). This must be explicitly imported in hosts that need container support.

**Module Pattern**: Each container service follows a standard pattern:
1. Module defines options in `modules/nixos/services/containers/{service}.nix`
2. Module is exported in `modules/nixos/default.nix`
3. Module is auto-imported to all hosts via `builtins.attrValues outputs.nixosModules`
4. Hosts enable and configure services by setting `services.containers.{service}.enable = true`
5. Configuration paths automatically use `hostSpec.persistFolder` for persistence

**Future Considerations**: The current implementation uses `virtualisation.oci-containers` which is the standard NixOS approach. For more advanced features like pod support (grouping multiple containers), better network management with subnets, or rootless containers via Home Manager, consider migrating to `quadlet-nix` (github:SEIAROTg/quadlet-nix). Quadlet provides native Podman Quadlet integration with declarative support for pods, networks, volumes, and auto-update functionality.

**Security Note**: Currently, containers run as systemd services under root. While Podman provides some isolation, this is not ideal from a security perspective. A future migration to quadlet-nix would enable proper rootless containers running as user services, providing better security isolation.

## Common Development Workflows

### Adding a New Host

1. Create directory: `hosts/{hostname}/`
2. Add `default.nix` importing hardware, disk layout, core, and optional features
3. Add `hardware-configuration.nix` (generate with `nixos-generate-config`)
4. Add host to `nixosConfigurations` in `flake.nix`
5. Create home-manager config: `home/sanfe/{hostname}.nix`
6. Add to `homeConfigurations` in `flake.nix`

### Adding Optional System Features

1. Create feature file in `hosts/optional/{feature}.nix`
2. Import in specific host's `default.nix`

### Adding Home-Manager Features

1. Create feature in `home/sanfe/features/{category}/{feature}/`
2. Import in host-specific `home/sanfe/{hostname}.nix`

### Adding Container Services

1. Create module in `modules/nixos/services/containers/{service}.nix` with options and config
2. Export module in `modules/nixos/default.nix`: `{service} = import ./services/containers/{service}.nix;`
3. Enable in host: `services.containers.{service}.enable = true;` with desired configuration
4. Import `hosts/optional/podman.nix` in host if not already imported

### Working with Secrets

```bash
# Edit common secrets (decrypts on-the-fly with your age key)
sops hosts/common/secrets.yaml

# Edit per-host secrets
sops hosts/asgard/secrets.yaml
```

### Testing Configuration Changes

1. Make changes to relevant `.nix` files
2. Format code: `nix fmt`
3. Quick syntax check: `nix eval .#nixosConfigurations.{hostname}.config.system.build.toplevel.drvPath`
4. Full check (slower): `nix flake check`
5. Activate (test, no boot entry): `sudo nixos-rebuild test --flake .#hostname`

## Operational Conventions

### Commit Style

- One-line conventional-commits messages: `type(scope): subject` (e.g. `fix(asgard): open port 53 in firewall`).
- No body, no `Co-Authored-By` trailer, no Claude attribution.
- Commits stay scoped: one logical change per commit. When the worktree has unrelated dirty files, use `git write-tree` / `git read-tree` to stage only the relevant subset.
- **Never `git push` until the change has been validated end-to-end on the affected host**. Local commits are fine; pushing without validation is not.

### Secrets Architecture (sops-nix)

- `.sops.yaml` lists three age recipients: the user `&sanfe` and one per host (`&asgard`, `&midgard`). The user key is derived from `~/.ssh/id_ed25519` (transitional — will move to YubiKey-backed GPG); each host key is derived from its `ssh_host_ed25519_key`.
- `hosts/common/secrets.yaml` is encrypted to user + all hosts (shared secrets, e.g. tailscale preauth).
- `hosts/{hostname}/secrets.yaml` is encrypted to user + that host only.
- `hosts/common/core/sops.nix` picks the per-host file when present and falls back to the common file.
- Workstations auto-bootstrap the user's age key via sops: if `user-age-keys/<username>` is populated in `hosts/common/secrets.yaml`, the activation script seeds `~/.config/sops/age/keys.txt` so `sops` works without manual setup.

**Adding a new secret**:
1. `sops hosts/common/secrets.yaml` (or the per-host file) and add the key.
2. Declare it in the consuming Nix module:
   ```nix
   sops.secrets."my-service/api-token" = {
     owner = "my-service";
     mode = "0400";
   };
   ```
3. Reference the materialized path: `config.sops.secrets."my-service/api-token".path`.
4. If a new host is added to `.sops.yaml`, re-encrypt existing files with `sops updatekeys hosts/common/secrets.yaml`.

### SSH

- All hosts ship an ed25519 `ssh_host_ed25519_key`; its public part is committed under `hosts/{hostname}/ssh_host_ed25519_key.pub` and converted to an age recipient.
- User SSH config lives in home-manager; `~/.ssh/lykill` is the current key used to reach `sanfe@192.168.1.54` (asgard) for remote deploys.

### Headscale Tailnet (`yggdrasil`)

The tailnet is self-hosted via headscale on bifrost. Key facts:

- Login server: `https://headscale.valgrindr.net` (Njalla A record, DDNS-refreshed by `hosts/bifrost/services/ddns.nix`)
- Base domain (Magic DNS): `ts.yggdrasil.lo`
- IPv4 prefix: `100.64.0.0/10` (midgard `100.64.0.1`, asgard `100.64.0.2`, bifrost `100.64.0.3` — fresh DB after the Phase 3 cutover, assignment is by enrollment order)
- DNS pushed to tailnet members: `192.168.1.55` (AdGuard on bifrost) — set in `services.headscale.settings.dns.nameservers.global`. Hosts that import `hosts/optional/tailscale.nix` come up with `--accept-dns=true`.
- Exit-node: bifrost (`hosts/optional/tailscale-exit-node.nix`). Auto-approved by the inline HuJSON policy (`autoApprovers.exitNode` for `group:exit-approvers`). Opt-in per client: `tailscale set --exit-node=bifrost`.
- Declarative bootstrap: `systemd.services.headscale-bootstrap` on bifrost seeds the SQLite DB with the `yggdrasil` user and a reusable preauth key (prefix + hash live in sops).

**Enrolling a new host**:
1. Add `hosts/optional/tailscale.nix` to the host's imports.
2. Ensure the host has access to the `tailscale-preauth-key` secret (it's already in `hosts/common/secrets.yaml`, so it works automatically once the host is in `.sops.yaml`).
3. On first boot, `tailscale-autoconnect-valgrindr.service` runs `tailscale up --login-server https://headscale.valgrindr.net --authkey <preauth>`.
4. Manual re-enroll if needed: `tailscale-login-valgrindr` (wrapper installed by the same module).

### LAN DNS (AdGuard Home on bifrost)

AdGuard Home on bifrost owns LAN DNS and is the authoritative resolver for `lan.valgrindr.net`:

- Bound to `0.0.0.0:53` (DoH to Quad9 upstream).
- WebUI on `127.0.0.1:3000`, reverse-proxied by Caddy at `https://adguard.lan.valgrindr.net` (TLS via the LE wildcard `*.lan.valgrindr.net`).
- Module: `hosts/bifrost/services/dns.nix`. Settings use `mutableSettings = false` so changes only happen through Nix.
- Rewrites point each `*.lan.valgrindr.net` name at the host that terminates TLS for it: bifrost-local names (`adguard`, `homepage`, `headplane`) → bifrost (`192.168.1.55`); every asgard app (Immich, Ghostfolio, Home Assistant, Firefly, the media stack) → asgard (`192.168.1.54`), which runs its own Caddy. bifrost no longer proxies asgard services.
- Workstations on the LAN reach AdGuard either directly (router DHCP advertises it — TODO) or via Magic DNS through tailscale.

**Gotchas worth memorizing**:
- `services.adguardhome.openFirewall = true` opens only the **webUI port**, NOT 53. Port 53 must be declared explicitly:
  ```nix
  networking.firewall.allowedTCPPorts = [53];
  networking.firewall.allowedUDPPorts = [53];
  ```
- AdGuard's settings schema puts rewrites under `filtering.rewrites`, **not** `dns.rewrites`. Each rewrite entry must include `enabled = true;` or the renderer marks it `enabled: false` and silently ignores it.
- `services.resolved.settings.Resolve.DNSStubListener = "no";` is required on the AdGuard host so systemd-resolved frees port 53.
- AdGuard's systemd unit uses `DynamicUser = true`, which puts state in `/var/lib/private/AdGuardHome` (bind-mounted to `/var/lib/AdGuardHome` per-service). Naïvely persisting `/var/lib/AdGuardHome` via `environment.persistence` conflicts with systemd's first-boot migration — leave it ephemeral until a `/var/lib/private` strategy is in place.
- AdGuard reads `/etc/hosts` by default. Any `networking.hosts."127.0.0.1" = ["foo.example"]` on the same host propagates as a `127.0.0.1` answer to **all** clients of that AdGuard. Don't do it unless you really mean it.

### Adding a new networked service

Ingress is per-host: the host that runs the service also terminates TLS for it. Both asgard and bifrost enable `services.caddyNjalla` (`modules/nixos/services/caddy-njalla.nix`) — a Caddy bundle with the Njalla DNS-01 plugin that auto-issues a wildcard LE cert for `*.lan.valgrindr.net`. Vhosts live inline next to each service.

1. Define the service in `hosts/<host>/services/<group>/<name>.nix` and bind it to `127.0.0.1:<port>`.
2. In the same file, declare the inline vhost:
   ```nix
   services.caddy.virtualHosts."${name}.lan.valgrindr.net".extraConfig = ''
     reverse_proxy 127.0.0.1:${toString port}
   '';
   ```
3. Secrets: `sops.secrets.…` (see "Working with Secrets" above).
4. Persistence: `environment.persistence."${config.hostSpec.persistFolder}".directories`.
5. DNS rewrite on bifrost: add to `services.adguardhome.settings.filtering.rewrites` in `hosts/bifrost/services/dns.nix` with `answer = "<host's LAN IP>"` and `enabled = true;` (use the `bifrostIp`/`asgardIp` constants).
6. Deploy the app host. Bifrost only needs a deploy if the rewrite list changed.

No firewall holes for backend ports, no cross-host Caddy handles, no `trusted_proxies` plumbing — Caddy and the backend share `127.0.0.1`.

> **Migration status.** The per-host-Caddy migration is done (Phases 0–5, see `docs/per-host-caddy-migration-plan.md`): every asgard app fronts itself with asgard's own Caddy, and bifrost's Caddy carries only its own local services (adguard, homepage, headplane) plus public headscale. There is exactly one ingress pattern now — the one documented above. Only the forward-looking Phase 6 (Authentik re-scope, doc-only) remains.

> **Public-domain exception**: `headscale.valgrindr.net` is public ingress (router → bifrost, LE via HTTP-01). That vhost lives in `hosts/bifrost/services/caddy.nix` and stays there — public ingress is out of scope for the per-host model.

## Active Hosts

- **midgard**: Main desktop (x86_64-linux, AMD CPU, xanmod kernel, Steam enabled). NixOS-integrated home-manager. Tailnet `100.64.0.1`.
- **asgard**: App server (Proxmox VM on the home LAN, x86_64-linux). Owns the finance stack (Firefly III, Ghostfolio, shared Postgres) and home-automation (Home Assistant, Mosquitto). Reachable at `192.168.1.54` on LAN and `100.64.0.2` on tailnet.
- **bifrost**: Networking host (Proxmox VM on the home LAN, x86_64-linux). Owns AdGuard (LAN DNS), headscale (tailnet control plane), Njalla DDNS for `headscale.valgrindr.net`, Caddy edge with LE wildcard cert for `*.lan.valgrindr.net` (Njalla DNS-01), and the tailnet exit-node role. Reachable at `192.168.1.55` on LAN and `100.64.0.3` on tailnet.

## Important Notes

- The configuration uses systemd-boot with a 3-second timeout.
- BTRFS subvolumes are used everywhere; wipe-on-boot is per-host (see Impermanence Strategy above).
- LUKS encryption is used on bare-metal (midgard); Proxmox VMs (asgard, bifrost) skip LUKS — the host already encrypts the underlying storage.
- The kernel is customized per-host (midgard uses `linux_xanmod_latest`).
- Cross-compilation is enabled for aarch64-linux and i686-linux on capable hosts.
