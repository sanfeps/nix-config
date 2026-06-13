{...}:
# Immich on asgard. The service contract (the upstream module, the local-Caddy
# vhost, /var/lib/immich persistence) lives in the reusable module
# `modules/homelab/services/immich` — this file only enables it, sets the
# asgard-specific knobs, and owns the pre-NAS storage backing.
#
# Status: ACTIVE in **pre-NAS mode**. The library lives at /mnt/nas/immich,
# backed by a local tmpfiles dir until the NAS lands. Once an NFS export
# exists, uncomment the fileSystems block below and the automount overlays the
# same path with no service-side change (same staging pattern as
# media/storage.nix).
#
# Caveat: pre-NAS, photo originals live on asgard's rootfs (no redundancy, no
# offsite backup). Don't load it up with anything irreplaceable until the NAS
# migration is done.
{
  homelab.services.immich = {
    enable = true;
    url = "immich.lan.valgrindr.net";
    # Backed by tmpfiles below pre-NAS; once the fileSystems block lands the
    # NFS automount overlays this exact path.
    mediaLocation = "/mnt/nas/immich";
    # machineLearning defaults to true (CPU-heavy); revisit if asgard struggles.
  };

  # TEMP(no-nas): back /mnt/nas/immich with a local dir so the service can come
  # up before the NAS is provisioned. Owned by immich:immich; the module writes
  # subdirs (library, thumbs, encoded-video, …) into it as it goes. When the
  # fileSystems block below is uncommented, the NFS automount overlays
  # /mnt/nas/immich and this underlying dir becomes invisible (harmless).
  # Remove these two lines at the same time the mount is wired in.
  systemd.tmpfiles.rules = [
    "d /mnt/nas        0755 root root -"
    "d /mnt/nas/immich 0700 immich immich -"
  ];

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
}
