# SSH & sops architecture

How this repo handles SSH identities, age keys, and encrypted secrets —
and what to do when you add a new host or reinstall an existing one.

## 1. The two SSH key families

There are two kinds of SSH keypair in this repo. They are unrelated even
though both end up under `~/.ssh/` or `/etc/ssh/`:

| Family | Whose identity? | How many? | Where does it live? | Used for |
|---|---|---|---|---|
| **Host key** | The **machine** | One per host | `/etc/ssh/ssh_host_ed25519_key` (bind-mounted from `/persist/etc/ssh/`) | (a) sshd identifies itself to clients, (b) sops-nix derives a host age recipient from it |
| **User auth key** | The **user** | One per human (currently `~/.ssh/id_ed25519`) | Workstation home dir | (a) SSH login to GitHub, other hosts, etc., (b) source of the user age key (today, see §3) |

Host keys are *server certificates*; the user key is *your passport*.
When sops needs to decide whether a given machine or human may decrypt a
secret, it converts the relevant public key to an age recipient and
consults `.sops.yaml`.

## 2. Recipient model in `.sops.yaml`

`.sops.yaml` enumerates two anchor lists and a small set of creation
rules:

```yaml
keys:
  - &users
    - &sanfe   age1dzpr70k…   # derived from sanfe's workstation SSH user pubkey
  - &hosts
    - &asgard  age1z2v…       # derived from asgard's SSH host pubkey
    - &midgard age1nryru…     # derived from midgard's SSH host pubkey
creation_rules:
  - path_regex: hosts/common/secrets\.ya?ml$
    key_groups:
      - age: [*sanfe, *asgard, *midgard]   # everybody who needs the file
  - path_regex: hosts/asgard/secrets\.ya?ml$
    key_groups:
      - age: [*sanfe, *asgard]             # only asgard's own secrets
```

When sops encrypts a file, it picks the first matching rule and encrypts
the payload symmetrically once, then wraps the symmetric key once per
recipient. Each recipient (user *or* host) can decrypt independently
with their own private key.

## 3. Age keys: where each one comes from

Three places, depending on identity type:

1. **Host age key** — derived on the fly from
   `/etc/ssh/ssh_host_ed25519_key` (the OpenSSH host key). sops-nix
   points at it via `sops.age.sshKeyPaths` in `hosts/common/core/sops.nix`.
   No separate file, no manual copy.

2. **User age key (today)** — derived from `~/.ssh/id_ed25519`. The
   user has to seed `~/.config/sops/age/keys.txt` once with
   `ssh-to-age -i ~/.ssh/id_ed25519` on their first workstation; on any
   subsequent workstation that imports the bootstrap (see §5), sops-nix
   writes it for you. `nix develop` sets `SOPS_AGE_KEY_FILE` to that
   path.

3. **User age key (post-YubiKey)** — replaced by a PGP fingerprint
   living in the YubiKey. The recipient in `.sops.yaml` changes from
   `age:` to `pgp:`. See `docs/yubikey-implementation-plan.md`.

## 4. Layout of secret files

```
nix-config/
├── .sops.yaml
└── hosts/
    ├── common/
    │   └── secrets.yaml         ← shared across every host
    ├── asgard/
    │   ├── secrets.yaml         ← decryptable by asgard + user
    │   └── ssh_host_ed25519_key.pub
    ├── midgard/
    │   └── ssh_host_ed25519_key.pub
    └── raidho/
        └── ssh_host_ed25519_key.pub
```

`hosts/common/core/sops.nix` sets `defaultSopsFile` to
`hosts/<hostName>/secrets.yaml` when that file exists, otherwise falls
back to `hosts/common/secrets.yaml`. Modules can override per-secret
with `sops.secrets.<name>.sopsFile = …` (the tailscale module does this
to read the shared preauth key from `hosts/common/secrets.yaml`).

## 5. Automatic user-age bootstrap on workstations

`hosts/common/core/sops.nix` conditionally declares a secret named
`user-age-keys/<username>` whose `path` is the user's
`~/.config/sops/age/keys.txt`. sops-nix writes the file on activation
with the right ownership; a small activation script fixes ownership of
`~/.config` so the user can keep using the rest of the directory
normally.

The declaration is gated by two conditions:

1. `hostSpec.profile == "workstation"` (set in
   `hosts/common/core/workstation.nix`, imported only by midgard and
   raidho), and
2. The string `user-age-keys` appears anywhere in
   `hosts/common/secrets.yaml`.

The second check works because sops only encrypts the *values* in a yaml
file, not the keys. The check evaluates `false` when the entry has not
been seeded yet, so the build does not fail before you populate it.

Practical consequence: provisioning a *second* workstation no longer
requires running `ssh-to-age` and copying `keys.txt` by hand. The host
decrypts the entry on first activation using its own SSH host key, and
the same file lands at the standard location ready for `sops`.

### Seeding the bootstrap (one-time per user)

```bash
nix shell nixpkgs#sops -c sops hosts/common/secrets.yaml
# Inside the editor, add:
#   user-age-keys:
#     sanfe: "AGE-SECRET-KEY-…"
# using the single-line contents of ~/.config/sops/age/keys.txt.
```

Then `nixos-rebuild switch` on each workstation. From this point on,
any fresh workstation install will materialise `~/.config/sops/age/keys.txt`
without manual ssh-to-age.

### Security note

Storing the user's age private key inside `hosts/common/secrets.yaml`
means any host listed as a recipient of that file can technically
extract it. Today that is asgard. If a server is fully compromised, the
attacker gains the user's age key (and, because today the user age key
is derived from `~/.ssh/id_ed25519`, also the user's GitHub SSH key).

Mitigations available:

* Once the user moves to a YubiKey-backed PGP recipient, this concern
  vanishes — the bootstrap entry can be removed.
* Or: move `user-age-keys/<user>` to a separate file
  (`hosts/common/workstation-secrets.yaml`) encrypted only to
  workstation hosts. Costs an extra creation rule and an extra file but
  isolates the blast radius.

## 6. Adding a brand new host

1. **Skeleton.** Create `hosts/<newhost>/{default.nix,hardware-configuration.nix}`
   following the pattern of `hosts/midgard/` (workstation) or
   `hosts/asgard/` (server). Workstations import
   `../common/core/workstation.nix`.

2. **flake.nix.** Add the host to `nixosConfigurations`. If you want a
   standalone `home-manager` configuration on it, add to
   `homeConfigurations` too — but on hosts that integrate home-manager
   via NixOS (currently midgard and raidho), you do not need this.

3. **Install NixOS.** Provision the host however you like (nixos-anywhere,
   live ISO, etc.). On first boot, sshd will generate
   `/etc/ssh/ssh_host_ed25519_key` automatically. sops-nix will fail to
   decrypt secrets on this first activation because the host's age
   recipient is not yet in `.sops.yaml` — that is expected, secrets-
   dependent services just won't start until we fix it.

4. **Capture the host's public key and age recipient.**
   ```bash
   ssh sanfe@<newhost> 'sudo cat /persist/etc/ssh/ssh_host_ed25519_key.pub' \
     > hosts/<newhost>/ssh_host_ed25519_key.pub
   nix shell nixpkgs#ssh-to-age -c \
     ssh-to-age < hosts/<newhost>/ssh_host_ed25519_key.pub
   ```
   Note the printed `age1…` recipient.

5. **`.sops.yaml`.** Add the recipient under `&hosts` and reference it
   in every `creation_rule` the host should be able to decrypt — at
   minimum `hosts/common/secrets.yaml`; also add a rule for
   `hosts/<newhost>/secrets.yaml` if you plan host-specific secrets.

6. **Re-encrypt.**
   ```bash
   sops updatekeys hosts/common/secrets.yaml
   # if the host has its own secrets file:
   sops updatekeys hosts/<newhost>/secrets.yaml
   ```

7. **Commit and redeploy.**
   ```bash
   git add hosts/<newhost>/ssh_host_ed25519_key.pub .sops.yaml hosts/**/secrets.yaml
   git commit -m "feat(<newhost>): add host"
   sudo nixos-rebuild switch --flake .#<newhost>   # or remote --target-host
   ```
   Secrets-dependent services now start cleanly.

8. **Verify.** SSH from another host should succeed without
   `knownHosts` warnings (the public key is in the repo and
   `hosts/common/core/openssh.nix` auto-populates `programs.ssh.knownHosts`).

## 7. Reinstalling an existing host

Reinstalling regenerates the host's SSH key, which means its age
recipient changes. You go through the same flow as §4–§7 of the new-host
section:

1. After reinstall, SSH in and copy
   `/persist/etc/ssh/ssh_host_ed25519_key.pub` over the old file in the
   repo.
2. Derive the new age recipient and replace the old anchor in
   `.sops.yaml`.
3. `sops updatekeys` on every affected file.
4. Commit and `nixos-rebuild switch` so the host can decrypt its
   secrets with its new identity.

If the host is a Tailscale/Headscale client, expect one extra manual
step on other nodes that knew it under its old NodeKey:
`tailscale-autoconnect-valgrindr` is `oneshot` and guards against a
working `BackendState`, so it won't re-register until something forces
it. On each affected client:

```bash
sudo tailscale logout
sudo systemctl restart tailscale-autoconnect-valgrindr
```

## 8. Removing a host

1. Delete `hosts/<host>/`.
2. Drop the recipient anchor and references from `.sops.yaml`.
3. `sops updatekeys` on every secrets file that referenced it.
4. Remove the entry from `flake.nix`.
5. Commit.

If you also want to revoke its tailnet membership: `headscale nodes
delete -i <id>` on asgard.

## 9. Forward path to YubiKey

When `docs/yubikey-implementation-plan.md` is executed, two things
change in this architecture and nothing else:

* The `&sanfe` recipient in `.sops.yaml` is rewritten from
  `age1dzpr70k…` to `pgp: <FINGERPRINT>`. Each `sops updatekeys` run
  thereafter requires a YubiKey touch.
* The `user-age-keys/<user>` bootstrap entry can be removed from
  `hosts/common/secrets.yaml`; the YubiKey now provides the user's sops
  identity directly, no on-disk file needed.

Host keys, host age recipients, and the per-host file layout remain
unchanged.
