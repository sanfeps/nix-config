{config, ...}:
# qBittorrent — download client confined to the Mullvad WireGuard namespace.
#
# Outbound: every byte goes through the tunnel; if the tunnel drops, the
# process loses egress entirely (kill-switch by construction — the netns
# has no default route outside WireGuard).
#
# Inbound (WebUI): asgard's own Caddy (per-host-caddy Phase 4) terminates TLS
# and reverse-proxies https://qbittorrent.lan.valgrindr.net → the netns veth
# IP 192.168.15.1:8080. Caddy connects over the mullvad-br bridge, so
# qBittorrent sees the source as 192.168.15.5 (the host bridge IP), not the
# original client — hence 192.168.15.0/24 is whitelisted below. See
# media/caddy.nix for the netns ingress reasoning.
#
# Auth: WebUI password skipped on LAN + tailnet + the bridge via
# AuthSubnetWhitelist. The netns accessibleFrom gates who can reach the port.
# No PBKDF2 hash to maintain in sops.
#
# Torrenting port: null. Mullvad does not forward ports, so we'd never
# accept incoming connections anyway. Leecher-only by design.
let
  webuiPort = 8080;
in {
  services.qbittorrent = {
    enable = true;
    openFirewall = false; # no LAN hole; local Caddy reaches it via the netns veth.
    inherit webuiPort;

    serverConfig = {
      # Auto-accept the EULA, otherwise qBittorrent blocks waiting for input.
      LegalNotice.Accepted = true;

      Preferences = {
        WebUI = {
          # Bind on all interfaces inside the netns; the netns is the gate.
          Address = "*";
          Port = webuiPort;

          # Skip password prompt from LAN/tailnet sources + the netns loopback
          # (Sonarr/Radarr live in the same netns and reach qBittorrent at
          # 127.0.0.1, so loopback must be whitelisted for downloads to flow
          # without a password being baked into the *arrs' download-client
          # config; the bootstrap reconciler relies on this too) + the
          # mullvad-br bridge (192.168.15.0/24) so asgard's local Caddy, which
          # proxies in from 192.168.15.5, is auth-bypassed too.
          AuthSubnetWhitelistEnabled = true;
          AuthSubnetWhitelist = "192.168.1.0/24,100.64.0.0/10,127.0.0.1/32,192.168.15.0/24";

          # Caddy rewrites the Host header.
          HostHeaderValidation = false;

          # TLS terminates on asgard's Caddy.
          HTTPS.Enabled = false;
        };
      };

      BitTorrent.Session = {
        DefaultSavePath = "/srv/media/downloads";
        TempPath = "/srv/media/downloads/.incomplete";
        TempPathEnabled = true;
      };
    };
  };

  # Shared traversal with the *arrs (Phase 3) over the downloads tree.
  users.users.qbittorrent.extraGroups = ["media"];

  # Persist torrent state (resume data, session, settings). The actual
  # download payloads live under /srv/media/downloads which is already
  # persisted globally via /srv.
  environment.persistence."${config.hostSpec.persistFolder}".directories = [
    {
      directory = "/var/lib/qBittorrent";
      user = "qbittorrent";
      group = "qbittorrent";
      mode = "0750";
    }
  ];

  # Confine the systemd unit to the Mullvad netns.
  systemd.services.qbittorrent.vpnConfinement = {
    enable = true;
    vpnNamespace = "mullvad";
  };

  # portMappings stays declared even though local Caddy reaches the WebUI via
  # the netns veth IP (192.168.15.1:8080) rather than the host-side DNAT: the
  # mapping installs the in-namespace veth INPUT ACCEPT rule for 8080. See
  # media/caddy.nix. The list merges with the *arr entries.
  vpnNamespaces.mullvad.portMappings = [
    {
      from = webuiPort;
      to = webuiPort;
      protocol = "tcp";
    }
  ];
}
