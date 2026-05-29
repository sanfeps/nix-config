# hosts/common/core

Minimal base config shared by every host. `default.nix` is just `import ./base.nix`, and `base.nix` is the actual entry point — it imports the rest of this directory and wires home-manager at the NixOS level.

## Load order matters

`base.nix` imports in this order:

1. `home-manager` NixOS module (so home-manager options exist for everything below)
2. `locale.nix` — timezone, console keymap, locale
3. `nix.nix` — nix daemon settings, garbage collection, registry pins, experimental features
4. `openssh.nix` — sshd config, host key types (ed25519 only — sops depends on it)
5. `sops.nix` — secrets, age recipients, user-age auto-bootstrap (see root `CLAUDE.md`)
6. `zsh.nix` — system-wide zsh enablement (home-manager owns user-level zsh)
7. `optin-persistence.nix` — base impermanence directories (`/var/lib/systemd`, `/var/lib/nixos`, `/var/log`, `/srv`, `/etc/machine-id`) and per-user `/persist/home/<user>` bootstrap
8. `persist-exceptions.nix` — `direnv-cleanup` oneshot that wipes persisted `.direnv` directories before user sessions
9. `modules/common/host-spec.nix` — declares the `hostSpec` option (username, profile, persistFolder)

It then imports every custom module from `outputs.nixosModules` (everything declared in `modules/nixos/default.nix`), so those modules are available on **every** host without per-host imports.

## Files NOT auto-imported

- `workstation.nix` — opt-in via the host's own `default.nix`. Marks `hostSpec.profile = "workstation"`, enables pipewire/rpcbind/mullvad, adds udev rules for dev hardware. The `profile` flag drives the user-age sops bootstrap and other workstation-only branches.
- `pipewire.nix`, `rpcbind.nix`, `mullvad-vpn.nix` — pulled in by `workstation.nix`.

## hostSpec defaults

`base.nix` sets:

- `hostSpec.username = "sanfe"`
- `hostSpec.persistFolder = "/persist"`

`networking.domain = "yggdrasil.lo"` is also set here (shared across the tailnet).

## Adding to base

When adding shared behavior:

- If **every** host needs it: add a file here and import it from `base.nix`.
- If **most** hosts need it: add it here but don't import from `base.nix` — leave the explicit opt-in (mirror `workstation.nix`).
- If only one host needs it: it doesn't belong here.

Things that DO belong: locale, nix settings, ssh, secrets, persistence wiring, system-wide shells/packages that have no per-host nuance.

Things that DO NOT: bootloader (per-host hardware), desktop environments (workstation-only), services (per-host or `hosts/optional/`).

## Impermanence

`optin-persistence.nix` is the floor — additional persistence belongs to whatever module owns the state. The pattern:

```nix
environment.persistence."${config.hostSpec.persistFolder}".directories = [
  { directory = "/var/lib/my-service"; user = "my-service"; group = "my-service"; mode = "0750"; }
];
```

Watch out for systemd `DynamicUser = true` services (e.g. AdGuard): they store state under `/var/lib/private/<name>` and a naive bind on `/var/lib/<name>` collides with systemd's own bind-mount. When in doubt, leave the directory ephemeral until you have a reproducible recipe.
