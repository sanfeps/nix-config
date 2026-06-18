# Keep the SSH host key stable on wipe-on-boot (impermanence) hosts.
#
# /etc lives on the ephemeral root subvolume that
# btrfs-luks-impermanence-disk.nix wipes every boot, so by default sshd
# regenerates a fresh ed25519 host key on each boot. That silently invalidates:
#   - hosts/<host>/ssh_host_ed25519_key.pub  -> breaks programs.ssh.knownHosts
#     pins ("REMOTE HOST IDENTIFICATION HAS CHANGED" after every reboot)
#   - the host's age recipient in .sops.yaml -> breaks host-key sops decryption
#
# We point services.openssh.hostKeys straight at /persist rather than
# bind-mounting the key into /etc/ssh: sops-nix needs the host key very early,
# before the impermanence bind-mounts are necessarily up, so a plain
# environment.persistence entry is not enough. (Same reasoning, and same fix, as
# upstream Misterio77/nix-config's hosts/common/global/openssh.nix.)
#
# This repo declares environment.persistence."/persist" on *every* host
# (including the non-wiped VMs asgard/bifrost), so upstream's
# `config.environment.persistence ? "/persist"` auto-detect can't distinguish
# impermanence here. Instead this module is imported only by the impermanence
# hosts (midgard, raidho); the VMs keep their key at /etc/ssh untouched.
#
# Prerequisite: seed the current live key into /persist BEFORE the first rebuild
# that enables this, or sshd will generate a brand-new key there:
#   sudo install -d -m700 /persist/etc/ssh
#   sudo cp -a /etc/ssh/ssh_host_ed25519_key{,.pub} /persist/etc/ssh/
{
  config,
  lib,
  ...
}: {
  services.openssh.hostKeys = lib.mkForce [
    {
      path = "${config.hostSpec.persistFolder}/etc/ssh/ssh_host_ed25519_key";
      type = "ed25519";
    }
  ];
}
