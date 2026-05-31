{pkgs, ...}:
# Bootstrap reconciler — runs once per boot, idempotently wires the *arr stack:
#
#   Prowlarr → Sonarr  (app registration, so Prowlarr pushes indexers to it)
#   Prowlarr → Radarr  (same)
#   Sonarr   → qBittorrent  (download client)
#   Radarr   → qBittorrent  (download client)
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
# What this script intentionally does NOT do:
#   - Seerr ↔ everything: Seerr's state directory has the DynamicUser
#     impermanence trap (see ./seerr.nix), so any wiring we'd do is lost
#     on reboot. Configure Seerr in its UI once and accept the limitation
#     until a /var/lib/private impermanence recipe lands.
#   - Root folders on Sonarr/Radarr: they point at /mnt/nas/media/library
#     which doesn't exist until the NAS is provisioned. Add the root
#     folders via UI (or extend this script) once the NAS mount is live.
#   - Quality profiles / custom formats: recyclarr owns those.
#
# Failure model: each reconciliation step logs and continues. A single
# unreachable peer should not prevent the others from being wired. The
# unit exits 0 even on partial failures so it doesn't endlessly restart;
# inspect `journalctl -u media-bootstrap` after deploys.
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
      CONFIGS = {
          "sonarr":   "/var/lib/sonarr/config.xml",
          "radarr":   "/var/lib/radarr/config.xml",
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

          log("done")


      if __name__ == "__main__":
          try:
              main()
          except Exception as e:
              log(f"FATAL: {e}")
              sys.exit(0)  # do not loop — log and move on
    '';
in {
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
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      Group = "root";
      ExecStart = "${reconciler}";
      # Best-effort: never fail the boot graph over reconciliation drift.
      SuccessExitStatus = "0 1";
    };
  };
}
