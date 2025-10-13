# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a personal NixOS configuration repository using a flake-based setup with home-manager integration. The configuration uses an impermanence strategy with BTRFS and LUKS encryption for most hosts.

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

```bash
# Build and activate home-manager configuration
home-manager switch --flake .

# Build for specific user@host
home-manager switch --flake .#sanfe@midgard
home-manager switch --flake .#sanfe@asgard
```

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
All hosts use impermanence with `/persist` as the persistence root. The root filesystem is ephemeral and gets wiped on reboot. Critical data is persisted through explicit declarations in home-manager and NixOS configurations.

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

#### Container Services
Declarative Podman container services are managed through custom NixOS modules located in `modules/nixos/services/containers/`. Each service module defines options and configuration for running containers via `virtualisation.oci-containers`.

**Base Configuration**: `hosts/optional/podman.nix` provides Podman with Docker compatibility, DNS-enabled networking, docker socket for rootless support, and management tools (podman-compose, podman-tui). This must be explicitly imported in hosts that need container support.

**Available Container Modules**:
- **Jellyfin** (`services.containers.jellyfin`): Media server with hardware acceleration support

**Module Pattern**: Each container service follows a standard pattern:
1. Module defines options in `modules/nixos/services/containers/{service}.nix`
2. Module is exported in `modules/nixos/default.nix`
3. Module is auto-imported to all hosts via `builtins.attrValues outputs.nixosModules`
4. Hosts enable and configure services by setting `services.containers.{service}.enable = true`
5. Configuration paths automatically use `hostSpec.persistFolder` for persistence

**Future Considerations**: The current implementation uses `virtualisation.oci-containers` which is the standard NixOS approach. For more advanced features like pod support (grouping multiple containers), better network management with subnets, or rootless containers via Home Manager, consider migrating to `quadlet-nix` (github:SEIAROTg/quadlet-nix). Quadlet provides native Podman Quadlet integration with declarative support for pods, networks, volumes, and auto-update functionality.

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

**Example**:
```nix
# In hosts/asgard/default.nix
{
  imports = [ ../optional/podman.nix ];

  services.containers.jellyfin = {
    enable = true;
    port = 8096;
    mediaPath = "/mnt/media";
    openFirewall = true;
  };
}
```

### Working with Secrets

```bash
# Edit secrets file (requires age key)
sops hosts/common/secrets.yaml

# Generate age key from SSH key
ssh-to-age -i ~/.ssh/id_ed25519 > ~/.config/sops/age/keys.txt
```

### Testing Configuration Changes

1. Make changes to relevant `.nix` files
2. Format code: `nix fmt`
3. Check syntax: `nix flake check`
4. Test build: `nixos-rebuild build --flake .#hostname` or `home-manager build --flake .#user@hostname`
5. Activate: `sudo nixos-rebuild test --flake .#hostname` (doesn't modify boot entries)

## Active Hosts

- **midgard**: Main desktop (x86_64-linux, AMD CPU, xanmod kernel, Steam enabled)
- **asgard**: Core server (Vultr, x86_64-linux)

## Important Notes

- The configuration uses systemd-boot with a 3-second timeout
- BTRFS subvolumes are used for snapshots and impermanence
- All hosts use LUKS encryption for the root partition
- The kernel is customized per-host (midgard uses linux_xanmod_latest)
- Cross-compilation is enabled for aarch64-linux and i686-linux on capable hosts
