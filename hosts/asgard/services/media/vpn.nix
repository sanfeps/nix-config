{
  config,
  inputs,
  ...
}:
# Mullvad WireGuard network namespace for the media acquisition plane.
#
# Egress chokepoint for qbittorrent + prowlarr + sonarr + radarr. Each
# confined service opts in with:
#
#   systemd.services.<name>.vpnConfinement = {
#     enable = true;
#     vpnNamespace = "mullvad";
#   };
#
# and exposes its WebUI back to the host via:
#
#   vpnNamespaces.mullvad.portMappings = [
#     { from = <hostPort>; to = <nsPort>; protocol = "tcp"; }
#   ];
#
# asgard's own Caddy then reverse-proxies https://<svc>.lan.valgrindr.net to
# the namespace veth IP 192.168.15.1:<nsPort> (see media/caddy.nix); the
# portMapping above is what installs the in-namespace veth INPUT ACCEPT.
#
# ──────────────────────────────────────────────────────────────────────────
# Mullvad wg conf bootstrap (one-time, manual):
#
#   1. Log in at mullvad.net → WireGuard configuration generator.
#      Generate a key, pick a single server, download the `.conf`.
#   2. Edit the conf locally:
#        - Confirm `DNS = 10.64.0.1` is present under [Interface]. If not,
#          add it. This is the leak-prevention belt to VPN-Confinement's
#          NSCD-socket suspenders (which are only tested for UDP DNS).
#        - Keep `Address`, `PrivateKey`, `[Peer]` block as-is.
#   3. `sops hosts/asgard/secrets.yaml` → add a key `media/mullvad-wg-conf`
#      with the full file content as a multiline string (`|` in yaml).
#   4. Deploy asgard. The namespace comes up at activation.
let
  ns = "mullvad"; # ≤7 chars; VPN-Confinement uses this as ifname suffix.
in {
  imports = [inputs.vpn-confinement.nixosModules.default];

  sops.secrets."media/mullvad-wg-conf" = {
    mode = "0400";
    # owner unset → root. VPN-Confinement's setup unit reads this at boot.
  };

  vpnNamespaces.${ns} = {
    enable = true;
    wireguardConfigFile = config.sops.secrets."media/mullvad-wg-conf".path;

    # Sources allowed to reach host-side port mappings published by confined
    # services. LAN for direct access, tailnet for remote admin, loopback
    # for any same-host proxy that lands here in the future.
    accessibleFrom = [
      "192.168.1.0/24"
      "100.64.0.0/10"
      "127.0.0.1/32"
    ];

    # portMappings is a list — each service module appends its own entry.
    # Defaults for namespaceAddress (192.168.15.1) are left untouched.
  };
}
