{
  config,
  lib,
  ...
}:
# Recyclarr — TRaSH-Guides sync. Declaratively keeps Sonarr/Radarr quality
# definitions and custom formats in lockstep with the upstream guides. Native
# NixOS module; runs as a daily systemd timer.
#
# Network model: Recyclarr lives OUTSIDE the VPN namespace. It only talks to
# the *arrs (over loopback via the port mappings published by their netns)
# and to api.github.com (over the host's normal egress) for the TRaSH repo.
# No tracker traffic, so confining it gains nothing and complicates routing.
#
# API key bootstrap: Sonarr/Radarr generate their API keys on first boot into
# their respective config.xml files (mode 0600, owned by the service user).
# A dedicated `recyclarr-credentials.service` oneshot runs as root before
# each recyclarr fire, extracts the keys, and stages them under
# /var/lib/recyclarr-credentials/. systemd's LoadCredential= then exposes
# them to recyclarr.service via $CREDENTIALS_DIRECTORY, and the module's
# preStart substitutes them into the rendered YAML.
#
# This is the same pattern Phase 6's reconciler uses for Prowlarr → *arrs
# wiring. Both run independently; nothing here depends on the reconciler.
#
# Scope: the config below seeds only quality_definition (series/movie size
# tiers). Custom formats are intentionally left empty — those are personal
# taste calls that should be added in a follow-up commit once the stack is
# bedded in. See https://recyclarr.dev/wiki/yaml/config-examples/ for the
# canonical TRaSH IDs once you're ready to layer on WEB-1080p / Bluray
# profiles and per-format scoring.
let
  credsDir = "/var/lib/recyclarr-credentials";
  sonarrKey = "${credsDir}/sonarr-api-key";
  radarrKey = "${credsDir}/radarr-api-key";

  # config.xml lives at <stateDir>/config.xml for both *arrs. Default
  # StateDirectory is /var/lib/{sonarr,radarr}; the `ApiKey` element is
  # plain text inside the XML so a one-shot xmllint extract is enough.
  sonarrConfig = "/var/lib/sonarr/config.xml";
  radarrConfig = "/var/lib/radarr/config.xml";
in {
  services.recyclarr = {
    enable = true;
    schedule = "daily";

    configuration = {
      sonarr.main = {
        base_url = "http://127.0.0.1:8989";
        api_key._secret = sonarrKey;
        quality_definition.type = "series";
      };
      radarr.main = {
        base_url = "http://127.0.0.1:7878";
        api_key._secret = radarrKey;
        quality_definition.type = "movie";
      };
    };
  };

  # Stage API keys from each *arr's config.xml before recyclarr fires.
  # Runs as root because /var/lib/{sonarr,radarr}/config.xml are 0600.
  # No RemainAfterExit: each timer activation re-extracts so if a service
  # is mid-rebuild and config.xml is briefly absent, the next cycle recovers.
  systemd.services.recyclarr-credentials = {
    description = "Stage *arr API keys for recyclarr";
    before = ["recyclarr.service"];
    requiredBy = ["recyclarr.service"];
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      Group = "root";
    };
    path = [];
    script = ''
      set -euo pipefail

      umask 077
      install -d -m 0700 -o root -g root ${credsDir}

      extract() {
        local cfg="$1" out="$2"
        if [ ! -r "$cfg" ]; then
          echo "recyclarr-credentials: $cfg unreadable — has the service ever started?" >&2
          exit 1
        fi
        # Naïve grep is enough: the *arr config.xml is flat XML with
        # <ApiKey>...</ApiKey> as a single line. Avoids pulling xmllint in.
        local key
        key="$(sed -n 's|.*<ApiKey>\(.*\)</ApiKey>.*|\1|p' "$cfg" | head -n1)"
        [ -n "$key" ] || { echo "recyclarr-credentials: empty ApiKey in $cfg" >&2; exit 1; }
        printf '%s' "$key" > "$out"
        chmod 0400 "$out"
      }

      extract ${sonarrConfig} ${sonarrKey}
      extract ${radarrConfig} ${radarrKey}
    '';
  };

  # Persist the state dir so the TRaSH-Guides cache survives reboots.
  # Recyclarr is a static user (the module declares it under users.users),
  # so naïve impermanence works — no DynamicUser trap here.
  environment.persistence."${config.hostSpec.persistFolder}".directories = [
    {
      directory = "/var/lib/recyclarr";
      user = "recyclarr";
      group = "recyclarr";
      mode = "0700";
    }
    {
      directory = credsDir;
      user = "root";
      group = "root";
      mode = "0700";
    }
  ];
}
