{
  pkgs,
  config,
  ...
}:
# Bootstrap reconciler — runs once per boot, idempotently wires the *arr stack:
#
#   Prowlarr → Sonarr  (app registration, so Prowlarr pushes indexers to it)
#   Prowlarr → Radarr  (same)
#   Sonarr   → qBittorrent  (download client)
#   Radarr   → qBittorrent  (download client)
#   Seerr    → Sonarr / Radarr  (request manager → automation)
#
# Two systemd units, by network reachability:
#
#   media-bootstrap         (runs inside the mullvad netns) — handles the
#                           four wirings above the Seerr line. Inside the
#                           netns 127.0.0.1:<port> reaches Sonarr/Radarr/
#                           Prowlarr/qBittorrent directly.
#
#   media-bootstrap-seerr   (runs on the host, outside the netns) — handles
#                           Seerr ↔ Sonarr/Radarr. Seerr lives outside the
#                           netns, so host loopback (127.0.0.1:5055) is the
#                           natural reach. The Sonarr/Radarr URLs we register
#                           inside Seerr's settings have to be reachable
#                           from Seerr at runtime — and Seerr (on host) can't
#                           reach the netns services via 127.0.0.1 or the
#                           host's own LAN IP (no OUTPUT-chain DNAT). The
#                           only working path is the bifrost edge:
#                           sonarr.lan.valgrindr.net:443 → bifrost Caddy →
#                           asgard:8989 (incoming) → PREROUTING DNAT → netns.
#                           Ugly round-trip via the edge, but it's the
#                           single working URL without patching VPN-Confinement.
#
# Why a reconciler instead of pre-seeding sops state:
#   - The *arrs auto-generate their API keys in config.xml on first boot.
#     Pre-seeding the key into config.xml fights with the module's
#     StateDirectory ownership and either races, fails, or silently no-ops.
#   - Cross-service URLs (e.g. "tell Prowlarr where Sonarr lives") need
#     each peer's API key, which is only known *after* that peer has booted
#     once. A boot-time reconciler is the cleanest expression of that.
#
# Idempotency model:
#   - GET the existing config from the target's REST API.
#   - If an entry with our managed name (Sonarr / Radarr / qBittorrent) is
#     absent → POST.
#   - If present → PUT (overwrites fields with our desired values, leaves
#     unrelated entries alone).
#
# What these scripts intentionally do NOT do:
#   - Root folders on Sonarr/Radarr: they point at /mnt/nas/media/library
#     which doesn't exist until the NAS is provisioned. Add the root
#     folders via UI (or extend this script) once the NAS mount is live.
#     The Seerr reconciler tolerates missing root folders — it skips the
#     Sonarr/Radarr registration with a log line instead of erroring.
#   - Seerr first-run wizard: Seerr requires manual Jellyfin-login + admin-
#     user creation through its web UI. The seerr reconciler waits for
#     settings.json.public.initialized == true before doing anything; until
#     the wizard runs once, this is a no-op.
#   - Quality profiles / custom formats: recyclarr owns those.
#
# Failure model: each reconciliation step logs and continues. A single
# unreachable peer should not prevent the others from being wired. The
# units exit 0 even on partial failures so they don't endlessly restart;
# inspect `journalctl -u media-bootstrap{,-seerr}` after deploys.
let
  reconciler =
    pkgs.writers.writePython3 "media-bootstrap" {
      # E241/E272 = aligned-column whitespace in dict/string literals — intentional.
      # E501 = long lines; W503 = line break before binary operator (modern PEP 8 prefers it).
      flakeIgnore = ["E241" "E272" "E501" "W503"];
    } ''
      """Reconcile *arr-stack inter-service wiring."""

      import json
      import os
      import re
      import sys
      import time
      import urllib.error
      import urllib.request
      from pathlib import Path

      HOST = "127.0.0.1"
      PORTS = {
          "qbittorrent": 8080,
          "prowlarr":    9696,
          "sonarr":      8989,
          "radarr":      7878,
      }
      # /api/v3 for Sonarr/Radarr, /api/v1 for Prowlarr (different lineage,
      # same underlying *arr framework). The /config/host endpoint we use
      # for the auth bypass takes the same shape across all three.
      API_VERSIONS = {
          "sonarr":   "v3",
          "radarr":   "v3",
          "prowlarr": "v1",
      }
      # The nixpkgs *arr modules drop config.xml under XDG-style paths.
      # Sonarr keeps the legacy NzbDrone name for back-compat; Radarr uses
      # its own. Prowlarr lives at the module's dataDir override.
      CONFIGS = {
          "sonarr":   "/var/lib/sonarr/.config/NzbDrone/config.xml",
          "radarr":   "/var/lib/radarr/.config/Radarr/config.xml",
          "prowlarr": "/srv/media/state/prowlarr/config.xml",
      }
      PING_PATHS = {
          # All *arrs respond on /ping with 200 once the SignalR/Jellyfin
          # boot dance settles. qBittorrent has no /ping; /api/v2/app/version
          # works equivalently for readiness.
          "sonarr":      "/ping",
          "radarr":      "/ping",
          "prowlarr":    "/ping",
          "qbittorrent": "/api/v2/app/version",
      }
      READY_TIMEOUT = 180


      def log(msg):
          print(f"[bootstrap] {msg}", flush=True)


      def extract_api_key(name):
          path = Path(CONFIGS[name])
          if not path.exists():
              raise FileNotFoundError(f"{name}: {path} missing (service never started?)")
          m = re.search(r"<ApiKey>([0-9a-f]+)</ApiKey>", path.read_text())
          if not m:
              raise ValueError(f"{name}: no <ApiKey> element in {path}")
          return m.group(1)


      def wait_ready(name, deadline):
          url = f"http://{HOST}:{PORTS[name]}{PING_PATHS[name]}"
          while time.time() < deadline:
              try:
                  with urllib.request.urlopen(url, timeout=3) as r:
                      if r.status < 500:
                          log(f"{name}: ready ({r.status} on {PING_PATHS[name]})")
                          return True
              except urllib.error.HTTPError as e:
                  if e.code < 500:
                      log(f"{name}: ready ({e.code} on {PING_PATHS[name]})")
                      return True
              except (urllib.error.URLError, ConnectionResetError, TimeoutError, OSError):
                  pass
              time.sleep(2)
          log(f"{name}: TIMEOUT waiting for {url}")
          return False


      def api(method, base_port, path, api_key, body=None):
          url = f"http://{HOST}:{base_port}{path}"
          req = urllib.request.Request(url, method=method)
          req.add_header("X-Api-Key", api_key)
          if body is not None:
              req.add_header("Content-Type", "application/json")
              data = json.dumps(body).encode()
          else:
              data = None
          with urllib.request.urlopen(req, data=data, timeout=15) as r:
              raw = r.read()
              return json.loads(raw) if raw else None


      def upsert(label, list_url_port, path, api_key, desired_by_name, list_path=None):
          """GET a list endpoint, POST/PUT entries keyed by .name."""
          list_path = list_path or path
          try:
              existing = api("GET", list_url_port, list_path, api_key) or []
          except urllib.error.HTTPError as e:
              log(f"{label}: GET {list_path} failed ({e.code}); skipping")
              return
          by_name = {e["name"]: e for e in existing}
          for name, body in desired_by_name.items():
              if name in by_name:
                  merged = {**by_name[name], **body}
                  merged["id"] = by_name[name]["id"]
                  try:
                      api("PUT", list_url_port, f"{path}/{merged['id']}", api_key, merged)
                      log(f"{label}: updated {name}")
                  except urllib.error.HTTPError as e:
                      log(f"{label}: PUT {name} failed ({e.code}): {e.read()[:200]!r}")
              else:
                  try:
                      api("POST", list_url_port, path, api_key, body)
                      log(f"{label}: created {name}")
                  except urllib.error.HTTPError as e:
                      log(f"{label}: POST {name} failed ({e.code}): {e.read()[:200]!r}")


      def reconcile_prowlarr_apps(keys):
          # Prowlarr ↔ Sonarr / Radarr application registration.
          # Implementation strings are stable across recent Prowlarr versions.
          desired = {}
          if "sonarr" in keys:
              desired["Sonarr"] = {
                  "name": "Sonarr",
                  "syncLevel": "fullSync",
                  "implementation": "Sonarr",
                  "configContract": "SonarrSettings",
                  "fields": [
                      {"name": "prowlarrUrl", "value": f"http://{HOST}:{PORTS['prowlarr']}"},
                      {"name": "baseUrl",     "value": f"http://{HOST}:{PORTS['sonarr']}"},
                      {"name": "apiKey",      "value": keys["sonarr"]},
                      {"name": "syncCategories", "value": [5000, 5010, 5020, 5030, 5040, 5045, 5050]},
                  ],
                  "tags": [],
              }
          if "radarr" in keys:
              desired["Radarr"] = {
                  "name": "Radarr",
                  "syncLevel": "fullSync",
                  "implementation": "Radarr",
                  "configContract": "RadarrSettings",
                  "fields": [
                      {"name": "prowlarrUrl", "value": f"http://{HOST}:{PORTS['prowlarr']}"},
                      {"name": "baseUrl",     "value": f"http://{HOST}:{PORTS['radarr']}"},
                      {"name": "apiKey",      "value": keys["radarr"]},
                      {"name": "syncCategories", "value": [2000, 2010, 2020, 2030, 2035, 2040, 2045, 2050, 2060]},
                  ],
                  "tags": [],
              }
          if desired:
              upsert("prowlarr-apps", PORTS["prowlarr"], "/api/v1/applications",
                     keys["prowlarr"], desired)


      def reconcile_arr_downloadclient(arr, keys):
          # Tell Sonarr/Radarr to use qBittorrent. Loopback whitelist on
          # qBittorrent (see qbittorrent.nix) means no username/password
          # is required from inside the netns.
          category = "tv-sonarr" if arr == "sonarr" else "movies-radarr"
          desired = {
              "qBittorrent": {
                  "name": "qBittorrent",
                  "enable": True,
                  "protocol": "torrent",
                  "priority": 1,
                  "removeCompletedDownloads": True,
                  "removeFailedDownloads": True,
                  "implementation": "QBittorrent",
                  "configContract": "QBittorrentSettings",
                  "fields": [
                      {"name": "host",      "value": HOST},
                      {"name": "port",      "value": PORTS["qbittorrent"]},
                      {"name": "useSsl",    "value": False},
                      {"name": "urlBase",   "value": ""},
                      {"name": "username",  "value": ""},
                      {"name": "password",  "value": ""},
                      {"name": "category",  "value": category},
                      {"name": "initialState", "value": 0},
                  ],
                  "tags": [],
              },
          }
          upsert(f"{arr}-downloadclient", PORTS[arr], "/api/v3/downloadclient",
                 keys[arr], desired)


      def reconcile_arr_auth(arr, api_key):
          """Disable login prompt for local (LAN) requests and seed the admin
          user. Modern *arrs require AuthenticationMethod to be set before
          the WebUI is usable, so we always provide a forms-based login as
          the fallback for off-LAN access. From bifrost (192.168.1.55 — a
          private-range IP from the *arr's perspective), the local-address
          check passes and the form is skipped entirely.
          """
          pwd = os.environ.get("ARR_ADMIN_PASSWORD")
          if not pwd:
              log(f"{arr}: ARR_ADMIN_PASSWORD not set in env; skipping auth reconcile")
              return
          ver = API_VERSIONS[arr]
          path = f"/api/{ver}/config/host"
          try:
              cur = api("GET", PORTS[arr], path, api_key)
          except urllib.error.HTTPError as e:
              log(f"{arr}: GET {path} failed ({e.code}); skipping auth")
              return
          if not isinstance(cur, dict):
              log(f"{arr}: unexpected GET {path} payload; skipping auth")
              return
          desired = {
              **cur,
              "authenticationMethod":   "forms",
              "authenticationRequired": "disabledForLocalAddresses",
              "username":               "admin",
              "password":               pwd,
              "passwordConfirmation":   pwd,
          }
          try:
              api("PUT", PORTS[arr], path, api_key, desired)
              log(f"{arr}: auth set to forms / disabledForLocalAddresses (admin seeded)")
          except urllib.error.HTTPError as e:
              log(f"{arr}: PUT {path} failed ({e.code}): {e.read()[:200]!r}")


      def main():
          deadline = time.time() + READY_TIMEOUT
          log("waiting for *arrs + qBittorrent to come up")
          for svc in ("sonarr", "radarr", "prowlarr", "qbittorrent"):
              wait_ready(svc, deadline)

          keys = {}
          for name in ("sonarr", "radarr", "prowlarr"):
              try:
                  keys[name] = extract_api_key(name)
                  log(f"{name}: extracted API key")
              except Exception as e:
                  log(f"{name}: could not extract API key — {e}")

          if "prowlarr" in keys:
              reconcile_prowlarr_apps(keys)
          else:
              log("prowlarr key missing; skipping app registration")

          for arr in ("sonarr", "radarr"):
              if arr in keys:
                  reconcile_arr_downloadclient(arr, keys)
              else:
                  log(f"{arr} key missing; skipping download-client wiring")

          for arr in ("sonarr", "radarr", "prowlarr"):
              if arr in keys:
                  reconcile_arr_auth(arr, keys[arr])

          log("done")


      if __name__ == "__main__":
          try:
              main()
          except Exception as e:
              log(f"FATAL: {e}")
              sys.exit(0)  # do not loop — log and move on
    '';

  # Separate reconciler for Seerr ↔ Sonarr/Radarr. Runs on the host (not
  # in the netns) because Seerr lives on the host network. See the header
  # comment block above for the routing rationale and the URL trick (the
  # bifrost edge is the only Seerr→*arr path that fires PREROUTING DNAT).
  seerrReconciler =
    pkgs.writers.writePython3 "media-bootstrap-seerr" {
      flakeIgnore = ["E241" "E272" "E501" "W503"];
    } ''
      """Reconcile Seerr ↔ Sonarr / Radarr (host-side, outside the netns)."""

      import json
      import re
      import sys
      import time
      import urllib.error
      import urllib.request
      from pathlib import Path

      HOST = "127.0.0.1"
      SEERR_PORT = 5055

      # Sonarr/Radarr config.xml — same paths as the netns-side reconciler,
      # repeated here so this script stands alone.
      ARR_CONFIGS = {
          "sonarr":   "/var/lib/sonarr/.config/NzbDrone/config.xml",
          "radarr":   "/var/lib/radarr/.config/Radarr/config.xml",
      }
      # Seerr's settings.json lives under the DynamicUser bind-mount.
      # Root traversal works fine (DynamicUser only changes ownership, not
      # mount visibility).
      SEERR_SETTINGS = "/var/lib/private/jellyseerr/settings.json"

      # Where Seerr should reach Sonarr/Radarr at runtime. NOT host-local —
      # Seerr is on the host, *arrs are in the netns, no OUTPUT-chain DNAT,
      # so 127.0.0.1 and 192.168.1.54 both fail. The bifrost edge is the
      # only LAN-routable path: traffic exits asgard, Caddy on bifrost
      # proxies it back, and the incoming connection on asgard hits
      # PREROUTING DNAT → netns service. Round-trip via 192.168.1.55 is the
      # cost of not patching VPN-Confinement's iptables.
      ARR_PROXIES = {
          "sonarr": ("sonarr.lan.valgrindr.net", 443, True),
          "radarr": ("radarr.lan.valgrindr.net", 443, True),
      }

      READY_TIMEOUT = 180


      def log(msg):
          print(f"[seerr-bootstrap] {msg}", flush=True)


      def extract_arr_api_key(name):
          path = Path(ARR_CONFIGS[name])
          if not path.exists():
              return None
          m = re.search(r"<ApiKey>([0-9a-f]+)</ApiKey>", path.read_text())
          return m.group(1) if m else None


      def extract_seerr_state():
          path = Path(SEERR_SETTINGS)
          if not path.exists():
              raise FileNotFoundError(f"{path} missing (Seerr never started?)")
          data = json.loads(path.read_text())
          api_key = data.get("main", {}).get("apiKey")
          if not api_key:
              raise ValueError("no main.apiKey in settings.json")
          initialized = bool(data.get("public", {}).get("initialized"))
          return api_key, initialized


      def http(method, url, api_key=None, body=None, timeout=15):
          req = urllib.request.Request(url, method=method)
          if api_key:
              req.add_header("X-Api-Key", api_key)
          if body is not None:
              req.add_header("Content-Type", "application/json")
              data = json.dumps(body).encode()
          else:
              data = None
          with urllib.request.urlopen(req, data=data, timeout=timeout) as r:
              raw = r.read()
              return json.loads(raw) if raw else None


      def wait_seerr_ready(deadline):
          url = f"http://{HOST}:{SEERR_PORT}/api/v1/status"
          while time.time() < deadline:
              try:
                  with urllib.request.urlopen(url, timeout=3) as r:
                      if r.status < 500:
                          log(f"seerr: ready ({r.status})")
                          return True
              except urllib.error.HTTPError as e:
                  if e.code < 500:
                      log(f"seerr: ready ({e.code})")
                      return True
              except (urllib.error.URLError, ConnectionResetError, TimeoutError, OSError):
                  pass
              time.sleep(2)
          log(f"seerr: TIMEOUT waiting for {url}")
          return False


      def fetch_first_profile_and_root(arr, arr_key):
          host, port, ssl = ARR_PROXIES[arr]
          scheme = "https" if ssl else "http"
          base = f"{scheme}://{host}:{port}"
          try:
              profiles = http("GET", f"{base}/api/v3/qualityprofile", arr_key) or []
              roots = http("GET", f"{base}/api/v3/rootfolder", arr_key) or []
          except urllib.error.HTTPError as e:
              log(f"{arr}: GET profiles/roots via {base} failed ({e.code}); skipping")
              return None, None
          except (urllib.error.URLError, TimeoutError, OSError) as e:
              log(f"{arr}: unreachable via {base} ({e}); skipping")
              return None, None
          if not profiles:
              log(f"{arr}: no quality profiles; skipping")
              return None, None
          if not roots:
              log(f"{arr}: no root folders configured (NAS not provisioned yet?); skipping")
              return None, None
          return profiles[0], roots[0]


      def reconcile_arr_in_seerr(arr, seerr_key, arr_key):
          profile, root = fetch_first_profile_and_root(arr, arr_key)
          if profile is None:
              return
          host, port, ssl = ARR_PROXIES[arr]
          body = {
              "name":               arr.capitalize(),
              "hostname":           host,
              "port":               port,
              "apiKey":             arr_key,
              "useSsl":             ssl,
              "baseUrl":            "",
              "activeProfileId":    profile["id"],
              "activeProfileName":  profile["name"],
              "activeDirectory":    root["path"],
              "is4k":               False,
              "isDefault":          True,
              "syncEnabled":        True,
          }
          if arr == "sonarr":
              body["enableSeasonFolders"] = True

          list_url = f"http://{HOST}:{SEERR_PORT}/api/v1/settings/{arr}"
          try:
              existing = http("GET", list_url, seerr_key) or []
          except urllib.error.HTTPError as e:
              log(f"seerr: GET /api/v1/settings/{arr} failed ({e.code}); skipping {arr}")
              return
          by_name = {e.get("name"): e for e in existing}
          if body["name"] in by_name:
              existing_entry = by_name[body["name"]]
              merged = {**existing_entry, **body, "id": existing_entry["id"]}
              try:
                  http("PUT", f"{list_url}/{existing_entry['id']}", seerr_key, merged)
                  log(f"seerr: updated {arr} registration")
              except urllib.error.HTTPError as e:
                  log(f"seerr: PUT {arr} failed ({e.code}): {e.read()[:200]!r}")
          else:
              try:
                  http("POST", list_url, seerr_key, body)
                  log(f"seerr: created {arr} registration")
              except urllib.error.HTTPError as e:
                  log(f"seerr: POST {arr} failed ({e.code}): {e.read()[:200]!r}")


      def main():
          deadline = time.time() + READY_TIMEOUT
          if not wait_seerr_ready(deadline):
              return

          try:
              seerr_key, initialized = extract_seerr_state()
              log("seerr: API key extracted")
          except Exception as e:
              log(f"seerr: could not extract API key — {e}")
              return
          if not initialized:
              log("seerr: setup wizard not yet completed (public.initialized != true); "
                  "skipping. Log into Seerr, finish the wizard, then "
                  "`systemctl start media-bootstrap-seerr`.")
              return

          for arr in ("sonarr", "radarr"):
              arr_key = extract_arr_api_key(arr)
              if not arr_key:
                  log(f"{arr}: API key unavailable; skipping")
                  continue
              try:
                  reconcile_arr_in_seerr(arr, seerr_key, arr_key)
              except Exception as e:
                  log(f"seerr: failed to reconcile {arr} — {e}")

          log("done")


      if __name__ == "__main__":
          try:
              main()
          except Exception as e:
              log(f"FATAL: {e}")
              sys.exit(0)
    '';
in {
  # Admin password shared across the three *arrs. We pre-seed all three
  # with the same `admin` user so off-LAN access (e.g. tailnet) still has
  # a working login; on-LAN access bypasses the form entirely via
  # AuthenticationRequired=DisabledForLocalAddresses.
  sops.secrets."media/arr-admin-password" = {
    mode = "0400";
    # owner unset → root (the reconciler runs as root).
  };

  sops.templates."media-bootstrap-env" = {
    content = ''
      ARR_ADMIN_PASSWORD=${config.sops.placeholder."media/arr-admin-password"}
    '';
    mode = "0400";
  };

  systemd.services.media-bootstrap = {
    description = "Reconcile *arr stack inter-service wiring";
    wantedBy = ["multi-user.target"];
    after = [
      "sonarr.service"
      "radarr.service"
      "prowlarr.service"
      "qbittorrent.service"
    ];
    wants = [
      "sonarr.service"
      "radarr.service"
      "prowlarr.service"
      "qbittorrent.service"
    ];
    # Run inside the mullvad netns so 127.0.0.1:<port> reaches the confined
    # services directly. The reconciler only talks to loopback APIs — no
    # internet egress needed — so the netns is a free win and dodges the
    # DNAT dance (VPN-Confinement only installs PREROUTING rules, which
    # don't fire on host-local loopback traffic). Filesystem access (the
    # config.xml extraction) is unaffected — netns only isolates networking.
    vpnConfinement = {
      enable = true;
      vpnNamespace = "mullvad";
    };
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      Group = "root";
      ExecStart = "${reconciler}";
      EnvironmentFile = config.sops.templates."media-bootstrap-env".path;
      # Best-effort: never fail the boot graph over reconciliation drift.
      SuccessExitStatus = "0 1";
    };
  };

  systemd.services.media-bootstrap-seerr = {
    description = "Reconcile Seerr ↔ Sonarr/Radarr";
    wantedBy = ["multi-user.target"];
    after = [
      "seerr.service"
      # Run after the netns-side reconciler so Sonarr/Radarr have any
      # required wiring (download client, etc.) in place before Seerr
      # validates the registration.
      "media-bootstrap.service"
    ];
    wants = [
      "seerr.service"
      "media-bootstrap.service"
    ];
    # Deliberately NOT inside the netns: Seerr lives on the host network,
    # and the *arr URLs we register (sonarr.lan.valgrindr.net etc.) only
    # resolve via the LAN AdGuard from outside the namespace.
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      Group = "root";
      ExecStart = "${seerrReconciler}";
      SuccessExitStatus = "0 1";
    };
  };
}
