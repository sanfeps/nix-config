{config, ...}:
# Immich on draupnir. The service contract (the upstream module, the
# local-Caddy vhost, /var/lib/immich persistence) lives in the reusable module
# `modules/homelab/services/immich` — this file only enables it and sets the
# draupnir-specific knobs.
#
# This is a FRESH install, not a data migration: the asgard instance was
# empty (pre-NAS scaffold, never loaded with photos), so it just gets
# decommissioned once this is validated — see
# docs/immich-draupnir-migration-runbook.md. The library lives directly on
# the raidz1 dataset at its canonical /tank/immich mountpoint; no asgard-era
# path compatibility to carry.
{
  homelab.services.immich = {
    enable = true;
    url = "immich.lan.valgrindr.net";
    # The tank/immich dataset (disko-data.nix). The upstream module's
    # tmpfiles rule chowns the mounted dir to immich:immich; Immich creates
    # its subtree (library/, upload/, thumbs/, …) from there.
    mediaLocation = "/tank/immich";
    # machineLearning stays on (default). 8 GiB is tight with ZFS ARC, so the
    # ARC is capped in ../default.nix; if memory pressure still shows up under
    # ML jobs, flipping this off is the next lever.
  };

  # Never let immich-server start against an unmounted library path — it
  # would write into the empty mountpoint dir on the NVMe rootfs.
  systemd.services.immich-server.unitConfig.RequiresMountsFor = [
    config.homelab.services.immich.mediaLocation
  ];

  # Declarative system settings (rendered to IMMICH_CONFIG_FILE). With this
  # set, the admin System Settings UI is read-only and every change goes
  # through Nix; keys not listed keep Immich's defaults. Schema:
  # https://immich.app/docs/install/config-file/
  # Note: machineLearning.urls is deliberately NOT set — its default comes
  # from the IMMICH_MACHINE_LEARNING_URL env the NixOS module wires to the
  # local ML service.
  services.immich.settings = {
    server.externalDomain = "https://immich.lan.valgrindr.net";
    # nixpkgs owns the version; don't phone github from the server.
    newVersionCheck.enabled = false;

    # Immich's own nightly pg dumps, written to <mediaLocation>/backups —
    # i.e. onto the raidz1 pool, covered by future tank/immich snapshots.
    backup.database = {
      enabled = true;
      cronExpression = "0 02 * * *";
      keepLastAmount = 14;
    };

    # Human-readable on-disk layout for new uploads instead of UUID paths.
    # Decided pre-first-upload on purpose: changing it later means running
    # the storage-migration job over the whole library.
    storageTemplate = {
      enabled = true;
      template = "{{y}}/{{MM}}/{{filename}}";
    };

    machineLearning = {
      # Smart search embeddings. Multilingual model instead of the default
      # ViT-B-32__openai (English-centric) so queries work in Spanish.
      # ~1 GiB heavier; if the model ever changes again, re-run the Smart
      # Search job (Admin → Jobs) to re-embed the existing library.
      clip = {
        enabled = true;
        modelName = "nllb-clip-base-siglip__v1";
      };
      facialRecognition.enabled = true;
      duplicateDetection.enabled = true;
    };

    # Keep ML/thumbnail jobs from ganging up on the 8 GiB box (ARC already
    # holds 3 GiB); throughput on bulk imports is the acceptable trade.
    job = {
      smartSearch.concurrency = 1;
      faceDetection.concurrency = 1;
      thumbnailGeneration.concurrency = 2;
      videoConversion.concurrency = 1;
    };

    trash = {
      enabled = true;
      days = 30;
    };
  };
}
