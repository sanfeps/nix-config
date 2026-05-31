{config, ...}:
# qBittorrent — download client confined to the Mullvad WireGuard namespace.
#
# Outbound: every byte goes through the tunnel; if the tunnel drops, the
# process loses egress entirely (kill-switch by construction — the netns
# has no default route outside WireGuard).
#
# Inbound (WebUI): VPN-Confinement forwards host:8080 → namespace:8080.
# Pattern-B firewall on the host limits the LAN side to bifrost only;
# Caddy on bifrost (Phase 4) will reverse-proxy
# https://qbittorrent.lan.valgrindr.net → 192.168.1.54:8080.
#
# Auth: WebUI password skipped on LAN + tailnet via AuthSubnetWhitelist.
# The Pattern-B firewall already gates who can reach the port; the netns
# accessibleFrom gates it again. No PBKDF2 hash to maintain in sops.
#
# Torrenting port: null. Mullvad does not forward ports, so we'd never
# accept incoming connections anyway. Leecher-only by design.
#
# Testing the WebUI during Phase 2 (before Caddy is wired in Phase 4):
# SSH-jump through bifrost — `ssh -L 8080:192.168.1.54:8080 sanfe@bifrost`
# and hit http://localhost:8080 in the browser. The bifrost-only firewall
# rule is what blocks direct LAN access until Caddy lands.
let
  webuiPort = 8080;
in {
  services.qbittorrent = {
    enable = true;
    openFirewall = false; # Pattern-B + VPN namespace handle this.
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
          # config; the bootstrap reconciler relies on this too).
          AuthSubnetWhitelistEnabled = true;
          AuthSubnetWhitelist = "192.168.1.0/24,100.64.0.0/10,127.0.0.1/32";

          # Caddy on bifrost rewrites the Host header.
          HostHeaderValidation = false;

          # TLS terminates on bifrost.
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

  # Publish the WebUI back to the host. The list merges with future *arr
  # entries that VPN-Confinement also exposes.
  vpnNamespaces.mullvad.portMappings = [
    {
      from = webuiPort;
      to = webuiPort;
      protocol = "tcp";
    }
  ];

  # Pattern-B firewall: only bifrost reaches asgard:8080 from the LAN.
  networking.firewall.extraCommands = ''
    iptables -I nixos-fw -p tcp --dport ${toString webuiPort} -s 192.168.1.55 -j nixos-fw-accept
  '';
}
