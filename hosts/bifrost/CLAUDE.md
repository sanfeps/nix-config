# bifrost

Networking host. Proxmox VM on the home LAN. The rainbow bridge between Asgard (apps) and everything else — owns DNS, headscale, public ingress (TLS termination with LE wildcard via Njalla DNS-01), and the tailnet exit-node role.

- LAN IP: DHCP for now (TODO: pin to `192.168.1.55` via router reservation once stable)
- Tailnet IP: assigned by headscale on first enrol (will be `100.64.0.3` if it lands in order)
- Hardware: serial console preserved (`console=ttyS0`); root on `/dev/sda` with btrfs + impermanence (VM, no LUKS).

## Current phase

**Phase 1 (this state)**: minimal bootstrap — core + tailscale only. Nothing else lives here yet. Asgard still owns AdGuard, headscale, DDNS, and Caddy.

Phase 2 and 3 (pending) will move the networking stack from asgard to here. Until cutover, the `tailscale-autoconnect-valgrindr` oneshot is the only thing this host does of interest.

## Bootstrap sequence (from-scratch install)

This host is brought up with `nixos-anywhere` from midgard, against a NixOS minimal installer running on the Proxmox VM. The hardware-configuration.nix is committed in this directory as a verbatim copy of asgard's (same Proxmox VM profile), so we don't need `--generate-hardware-config`:

```bash
nix run github:nix-community/nixos-anywhere -- \
  -i ~/.ssh/lykill \
  --flake .#bifrost \
  --target-host root@<installer-ip>
```

If Proxmox configuration ever differs between hosts (different disk controller, different NIC), regenerate with `nixos-generate-config --show-hardware-config` from the installer and replace the file.

**Note**: `hosts/bifrost/ssh_host_ed25519_key.pub` is currently a placeholder ed25519 key — needed only so the flake evaluates (every host in `nixosConfigurations` must have one for the `programs.ssh.knownHosts` loop). It is NOT the real key bifrost will boot with; nixos-anywhere generates the real one on first deploy. After first boot you MUST replace it.

After first boot:

1. SSH in (`ssh sanfe@<bifrost-ip>`) and overwrite the placeholder with the real key:
   ```bash
   ssh sanfe@<bifrost-ip> 'sudo cat /persist/etc/ssh/ssh_host_ed25519_key.pub' \
     > hosts/bifrost/ssh_host_ed25519_key.pub
   ```
2. Derive the age recipient (`ssh-to-age < hosts/bifrost/ssh_host_ed25519_key.pub`) and add to `.sops.yaml` as `&bifrost`.
3. Add `*bifrost` to the `hosts/common/secrets.yaml` key group and run `sops updatekeys hosts/common/secrets.yaml` so `tailscale-preauth-key` can be decrypted on bifrost.
4. Redeploy. `tailscale-autoconnect-valgrindr.service` runs and enrols bifrost into the yggdrasil tailnet automatically.

## Deploys (after bootstrap)

```bash
NIX_SSHOPTS="-i ~/.ssh/lykill" nixos-rebuild switch --flake .#bifrost \
  --target-host sanfe@<bifrost-ip> --build-host sanfe@<bifrost-ip> \
  --ask-sudo-password
```

Same `trusted-users`-off pattern as asgard: always build on the remote, never push pre-built closures.
