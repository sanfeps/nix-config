{
  config,
  lib,
  pkgs,
  ...
}:
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
        # Downloads land on the NAS (draupnir tank/media over NFSv4), NOT on
        # asgard's local disk. Two big concurrent downloads used to fill
        # /srv/media/downloads → asgard's disk + the Proxmox thin-pool → 100%
        # → the VM froze into io-error (same class as the 2026-07-26 crash).
        # Writing to /mnt/nas/media/downloads offloads that growth to the pool.
        #
        # Same-dataset staging: downloads is a *subdirectory* of the tank/media
        # dataset (not a child dataset), same filesystem as
        # /mnt/nas/media/library — so Sonarr/Radarr's `Move` import is an atomic
        # server-side rename, not a byte copy (faster than the old local→NFS
        # copy). draupnir creates the dir setgid media(1500) — see nfs.nix.
        #
        # Netns note: qBittorrent runs in the Mullvad netns, but the NFS client
        # transport is bound to the netns the mount was created in (the host's),
        # not the writing process's. So these writes egress asgard→draupnir over
        # the LAN, while peer/tracker traffic still goes through the tunnel — no
        # leak, and the storage write doesn't pay tunnel overhead.
        DefaultSavePath = "/mnt/nas/media/downloads";
        TempPath = "/mnt/nas/media/downloads/.incomplete";
        TempPathEnabled = true;

        # Leecher-only cleanup. Mullvad forwards no ports, so we can't seed
        # meaningfully — cap the share ratio at 0 (satisfied the moment a
        # download completes) and just PAUSE the torrent when reached. We
        # deliberately do NOT "remove + delete files" here: that would race the
        # *arr and could delete the payload before Sonarr/Radarr import it.
        # Instead, the paused torrent reads as "done seeding", which lets the
        # *arrs' removeCompletedDownloads (bootstrap.nix) remove the torrent and
        # delete the NAS staging copy after import. Without this cap the torrent seeds
        # forever, the *arr never considers it finished, and nothing is cleaned
        # up (the symptom: completed films linger + keep "sharing").
        # MaxRatioAction: 0 = Pause, 1 = Remove, 2 = Remove+delete files.
        GlobalMaxRatio = 0.0;
        MaxRatioAction = 0;
      };
    };
  };

  # Self-heal the single-instance lockfile. If qBittorrent is SIGKILLed — e.g. a
  # deploy/restart whose stop exceeds the timeout, or a netns (BindsTo=mullvad)
  # cascade — it leaves a stale `config/lockfile` behind, and every subsequent
  # start then sees it, assumes another instance is running, and immediately
  # quits (log: "termination initiated" / "ready to exit", exit 0, WebUI never
  # binds). systemd already guarantees a single instance of this unit, so
  # clearing the lock before each start is safe and idempotent (rm -f is a no-op
  # when absent). mkAfter appends to the module's own ExecStartPre (the conf
  # install) rather than replacing it. Backstory + manual recovery: CLAUDE.md.
  # This is deliberately NOT in the bootstrap reconciler — that reconciles config
  # via APIs and runs once after the services; process-liveness self-healing
  # belongs on the unit, where it runs before every (re)start.
  systemd.services.qbittorrent.serviceConfig.ExecStartPre = lib.mkAfter [
    "${pkgs.coreutils}/bin/rm -f /var/lib/qBittorrent/qBittorrent/config/lockfile"
  ];

  # Shared traversal with the *arrs (Phase 3) over the downloads tree.
  users.users.qbittorrent.extraGroups = ["media"];

  # Group-writable downloads (umask 0002 → dirs 0775 / files 0664). REQUIRED now
  # that downloads live in the same NAS dataset as the library: Sonarr/Radarr
  # import by renaming the file straight out of qBittorrent's download dir, which
  # needs WRITE on that dir. With the default umask 0022 qBittorrent creates its
  # per-torrent dirs 0755 (group `media` can't write), so the *arrs (group media,
  # not owner) fail the move with `IOException: Permission denied`; the import
  # fails and — since removal is gated on a *successful* import — the torrent is
  # never cleaned up (symptom: completed downloads pile up, never deleted). On
  # the old local /srv layout this was hidden: that import was a cross-filesystem
  # COPY (read-only source) + qBittorrent deleting its OWN files, so the group-
  # write gap never mattered. Same reason the other writers set umask 002
  # (music-dl.nix); see storage.nix / the media CLAUDE.md setgid note.
  systemd.services.qbittorrent.serviceConfig.UMask = "0002";

  # Persist torrent state (resume data, session, settings). The actual
  # download payloads live on the NAS (/mnt/nas/media/downloads → draupnir
  # tank/media), so they're not asgard's to persist.
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
