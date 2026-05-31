{
  config,
  lib,
  ...
}:
# Immich — self-hosted photo/video library.
#
# Status: scaffolded but NOT YET ACTIVE. The import in `services/default.nix`
# is commented out because the media library has to live on the NAS, and the
# NAS hasn't been provisioned yet. See "Activation checklist" at the bottom.
#
# Topology follows Pattern B (CLAUDE.md): immich listens off-loopback on
# asgard, firewall locks the port to bifrost (192.168.1.55), and bifrost
# terminates TLS + reverse-proxies to https://immich.lan.valgrindr.net.
# Unlike Firefly, Immich honours X-Forwarded-Proto out of the box — no
# FastCGI HTTPS=on hack needed.
let
  port = 2283;
  virtualHost = "immich.lan.valgrindr.net";
in {
  services.immich = {
    enable = true;
    host = "0.0.0.0";
    inherit port;
    # Library on the NAS — see the fileSystems TODO at the bottom. The immich
    # NixOS module says the directory has to exist and be writable by the
    # immich user; the NAS export needs to honour that (NFS no_root_squash off,
    # plus an `anonuid`/`anongid` matching immich's uid/gid, or an explicit
    # acl entry — depends on the NAS).
    mediaLocation = "/mnt/nas/immich";

    # Postgres + Redis + pgvector/vectorchord are configured automatically by
    # the module. Postgres uses the shared instance on asgard (peer auth via
    # /run/postgresql), Redis gets a dedicated unix-socket server. Both opt-in
    # defaults are fine; no need to override.

    # machine-learning is on by default and produces face/object embeddings.
    # Heavy on CPU; leave on for now and revisit if asgard struggles.
    machine-learning.enable = true;
  };

  # Only bifrost reaches :2283 from off-host. iptables backend (asgard is the
  # legacy nftables-off host); same pattern as firefly/home-assistant.
  networking.firewall.extraCommands = ''
    iptables -I nixos-fw -p tcp --dport ${toString port} -s 192.168.1.55 -j nixos-fw-accept
  '';

  # ---------------------------------------------------------------------------
  # Activation checklist (when the NAS lands):
  #
  #  1. Provision the NAS, expose `/immich` (or whichever path) over NFS/CIFS.
  #  2. Fill in the fileSystems block below with the real device+options,
  #     uncomment it, and remove this checklist.
  #  3. Uncomment the import in hosts/asgard/services/default.nix.
  #  4. Add the bifrost-side bits (template below) and redeploy bifrost.
  #  5. Deploy asgard. systemd-tmpfiles will not create /mnt/nas/immich for
  #     us — the fileSystems mount has to be up *before* immich-server starts.
  #     The module already pulls in network-online.target; add an explicit
  #     `RequiresMountsFor=/mnt/nas/immich` on the immich-server unit if the
  #     mount turns out racy.
  #
  # fileSystems."/mnt/nas/immich" = {
  #   device = "TODO-nas.lan.valgrindr.net:/volume1/immich";  # or //nas/share for CIFS
  #   fsType = "nfs";                                         # or "cifs"
  #   options = [
  #     "x-systemd.automount"   # mount on first access, not at boot
  #     "noauto"
  #     "_netdev"               # wait for network
  #     "soft"                  # don't hang on NAS outage
  #     "timeo=30"
  #   ];
  # };
  #
  # Bifrost-side additions (in hosts/bifrost/services/caddy.nix inside the
  # *.lan.valgrindr.net vhost):
  #
  #   @immich host immich.lan.valgrindr.net
  #   handle @immich {
  #     reverse_proxy 192.168.1.54:2283
  #   }
  #
  # And in hosts/bifrost/services/dns.nix, add a rewrite:
  #
  #   { domain = "immich.lan.valgrindr.net"; answer = bifrostIp; enabled = true; }
  # ---------------------------------------------------------------------------

  # Persistence note: immich state (DB, thumbnails, encoded video, ML models)
  # lives under /var/lib/immich which we persist below. The actual photo/video
  # originals live on the NAS via mediaLocation, so they're not in /persist.
  environment.persistence."${config.hostSpec.persistFolder}".directories = [
    {
      directory = "/var/lib/immich";
      user = config.services.immich.user;
      group = config.services.immich.group;
      mode = "0700";
    }
  ];
}
