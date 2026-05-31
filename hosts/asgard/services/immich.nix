{
  config,
  lib,
  ...
}:
# Immich — self-hosted photo/video library.
#
# Status: ACTIVE in **pre-NAS mode**. The photo library lives at
# /mnt/nas/immich, which is backed by a local tmpfiles directory until the
# NAS lands. Once an NFS export exists, uncomment the fileSystems block at
# the bottom of this file and the NFS automount overlays the same path with
# no service-side change (same staging pattern as media/storage.nix).
#
# Caveat: pre-NAS, photo originals live on asgard's rootfs (no redundancy,
# no offsite backup). Don't load it up with anything irreplaceable until
# the NAS migration is done.
#
# Topology follows Pattern B (CLAUDE.md): immich listens off-loopback on
# asgard, firewall locks the port to bifrost (192.168.1.55), and bifrost
# terminates TLS + reverse-proxies to https://immich.lan.valgrindr.net.
# Unlike Firefly, Immich honours X-Forwarded-Proto out of the box — no
# FastCGI HTTPS=on hack needed.
let
  port = 2283;
in {
  services.immich = {
    enable = true;
    host = "0.0.0.0";
    inherit port;
    # Backed by tmpfiles below pre-NAS; once the fileSystems block lands the
    # NFS automount overlays this exact path.
    mediaLocation = "/mnt/nas/immich";

    # Postgres + Redis + pgvector/vectorchord are configured automatically by
    # the module. Postgres uses the shared instance on asgard (peer auth via
    # /run/postgresql), Redis gets a dedicated unix-socket server. Both opt-in
    # defaults are fine; no need to override.

    # machine-learning is on by default and produces face/object embeddings.
    # Heavy on CPU; leave on for now and revisit if asgard struggles.
    machine-learning.enable = true;
  };

  # TEMP(no-nas): back /mnt/nas/immich with a local dir so the service can come
  # up before the NAS is provisioned. Owned by immich:immich; the module
  # writes subdirs (library, thumbs, encoded-video, …) into it as it goes.
  # When the fileSystems block below is uncommented, the NFS automount
  # overlays /mnt/nas/immich and this underlying dir becomes invisible
  # (harmless). Remove these two lines at the same time the mount is wired in.
  systemd.tmpfiles.rules = [
    "d /mnt/nas        0755 root root -"
    "d /mnt/nas/immich 0700 immich immich -"
  ];

  # Only bifrost reaches :2283 from off-host. iptables backend (asgard is the
  # legacy nftables-off host); same pattern as firefly/home-assistant.
  networking.firewall.extraCommands = ''
    iptables -I nixos-fw -p tcp --dport ${toString port} -s 192.168.1.55 -j nixos-fw-accept
  '';

  # ---------------------------------------------------------------------------
  # NAS activation checklist (when the NAS lands):
  #
  #  1. Provision the NAS, expose `/immich` (or whichever path) over NFS/CIFS.
  #     The export needs to honour immich's uid/gid (anonuid/anongid or an
  #     explicit ACL entry — depends on the NAS).
  #  2. Fill in the fileSystems block below with the real device+options,
  #     uncomment it, drop the TEMP(no-nas) tmpfiles entries above.
  #  3. Before redeploying, copy any pre-NAS photo state off the local
  #     /mnt/nas/immich (or just accept that it gets shadowed and migrate
  #     via the immich UI).
  #  4. Deploy. systemd-tmpfiles will not create /mnt/nas/immich for us —
  #     the fileSystems mount has to be up *before* immich-server starts.
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
