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
#   - Private / auth-bearing indexers: any indexer requiring an API key or
#     login belongs in the Prowlarr UI, not in Nix-controlled state (would
#     leak secrets through the reconciler). The PUBLIC_INDEXERS list below
#     covers the public+free indexers we want everywhere by default.
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
      # Where the *arrs put their imports. Backed by tmpfiles dirs in
      # storage.nix while the NAS isn't provisioned; once the NFS mount
      # lands the same paths are overlaid by the remote share.
      ROOT_FOLDERS = {
          "sonarr": "/mnt/nas/media/library/tv",
          "radarr": "/mnt/nas/media/library/movies",
      }
      # Cardigann YAML definition names for public, auth-free indexers we
      # want auto-enabled in Prowlarr. Anything requiring API keys or login
      # (private trackers, Jackett-style auth) belongs in the UI — kept out
      # of declarative state so secrets don't leak through the reconciler.
      PUBLIC_INDEXERS = [
          "internetarchive",  # Internet Archive — public domain / CC torrents
      ]
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


      def reconcile_prowlarr_indexers(api_key):
          """Auto-enable a curated list of public Cardigann indexers.

          We GET /api/v1/indexer/schema (the template catalog Prowlarr ships
          with), pick the entry whose `definitionName` matches each desired
          indexer, drop the schema's id, and POST it as a real indexer.
          Prowlarr's Apps sync (already configured via reconcile_prowlarr_apps)
          then pushes the new indexer to Sonarr/Radarr automatically.
          """
          list_url = "/api/v1/indexer"
          schema_url = "/api/v1/indexer/schema"
          try:
              existing = api("GET", PORTS["prowlarr"], list_url, api_key) or []
          except urllib.error.HTTPError as e:
              log(f"prowlarr-indexers: GET {list_url} failed ({e.code}); skipping")
              return
          existing_defs = {
              idx.get("definitionName")
              for idx in existing
              if idx.get("definitionName")
          }
          missing = [d for d in PUBLIC_INDEXERS if d not in existing_defs]
          if not missing:
              log("prowlarr-indexers: all targets already present")
              return
          try:
              schemas = api("GET", PORTS["prowlarr"], schema_url, api_key) or []
          except urllib.error.HTTPError as e:
              log(f"prowlarr-indexers: GET {schema_url} failed ({e.code}); skipping")
              return
          schemas_by_def = {
              s.get("definitionName"): s
              for s in schemas
              if s.get("definitionName")
          }
          # Prowlarr requires a non-zero appProfileId on POST. The default profile
          # ("Standard", id=1) is created on first boot — pick it dynamically so
          # we don't hardcode the id.
          try:
              profiles = api("GET", PORTS["prowlarr"], "/api/v1/appprofile", api_key) or []
          except urllib.error.HTTPError as e:
              log(f"prowlarr-indexers: GET /appprofile failed ({e.code}); skipping")
              return
          if not profiles:
              log("prowlarr-indexers: no app profiles found; skipping")
              return
          app_profile_id = profiles[0]["id"]
          for d in missing:
              schema = schemas_by_def.get(d)
              if not schema:
                  candidates = [n for n in schemas_by_def if d.lower() in n.lower()]
                  log(f"prowlarr-indexers: no schema matching definitionName={d!r}; "
                      f"candidates containing {d!r}: {candidates[:5]}")
                  continue
              body = {**schema, "enable": True, "appProfileId": app_profile_id}
              body.pop("id", None)
              try:
                  api("POST", PORTS["prowlarr"], list_url, api_key, body)
                  log(f"prowlarr-indexers: added {schema.get('name', d)!r} (definitionName={d})")
              except urllib.error.HTTPError as e:
                  log(f"prowlarr-indexers: POST for {d} failed ({e.code}): {e.read()[:300]!r}")


      def reconcile_arr_root_folder(arr, api_key):
          """Ensure Sonarr/Radarr has its library root folder registered.
          The *arr validates the path exists + is writable; storage.nix
          pre-creates the dirs as tmpfiles entries, so this works pre-NAS.
          """
          path = ROOT_FOLDERS[arr]
          api_path = f"/api/{API_VERSIONS[arr]}/rootfolder"
          try:
              existing = api("GET", PORTS[arr], api_path, api_key) or []
          except urllib.error.HTTPError as e:
              log(f"{arr}: GET {api_path} failed ({e.code}); skipping root folder")
              return
          if any(rf.get("path") == path for rf in existing):
              log(f"{arr}: root folder {path} already present")
              return
          try:
              api("POST", PORTS[arr], api_path, api_key, {"path": path})
              log(f"{arr}: added root folder {path}")
          except urllib.error.HTTPError as e:
              log(f"{arr}: POST {api_path} failed ({e.code}): {e.read()[:200]!r}")


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
              reconcile_prowlarr_indexers(keys["prowlarr"])
          else:
              log("prowlarr key missing; skipping app + indexer registration")

          for arr in ("sonarr", "radarr"):
              if arr in keys:
                  reconcile_arr_downloadclient(arr, keys)
                  reconcile_arr_root_folder(arr, keys[arr])
              else:
                  log(f"{arr} key missing; skipping download-client + root folder wiring")

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
      import os
      import re
      import sys
      import time
      import urllib.error
      import urllib.request
      from pathlib import Path

      HOST = "127.0.0.1"
      SEERR_PORT = 5055
      JELLYFIN_PORT = 8096
      JELLYFIN_EXTERNAL = "https://jellyfin.lan.valgrindr.net"

      # Sonarr/Radarr config.xml — same paths as the netns-side reconciler,
      # repeated here so this script stands alone.
      ARR_CONFIGS = {
          "sonarr":   "/var/lib/sonarr/.config/NzbDrone/config.xml",
          "radarr":   "/var/lib/radarr/.config/Radarr/config.xml",
      }
      # Seerr's settings.json lives under the DynamicUser bind-mount, inside
      # a `config/` subdir (legacy from jellyseerr's docker container where
      # the bind-mount target was /app/config). Root traversal works fine —
      # DynamicUser only changes ownership, not mount visibility.
      SEERR_SETTINGS = "/var/lib/private/jellyseerr/config/settings.json"

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


      def reconcile_seerr_wizard():
          """Replicate Seerr's first-run wizard via API:
            1. POST /api/v1/auth/jellyfin — log into Jellyfin and create the
               Seerr admin user mirroring it. Required for the wizard to
               consider itself "done".
            2. POST /api/v1/settings/jellyfin — persist the Jellyfin
               connection. /auth/jellyfin saves a partial copy already, but
               this also seeds the externalHostname used by Seerr's UI
               links back to Jellyfin.
            3. POST /api/v1/settings/initialize — flip public.initialized.

          Idempotent: re-running just logs the existing admin in.
          """
          jf_user = os.environ.get("JELLYFIN_ADMIN_USERNAME")
          jf_pwd = os.environ.get("JELLYFIN_ADMIN_PASSWORD")
          if not (jf_user and jf_pwd):
              log("seerr: Jellyfin admin creds missing in env; cannot auto-run wizard. "
                  "Add media/jellyfin-admin-{username,password} to sops, or finish "
                  "Seerr's wizard manually in the web UI.")
              return False

          # Step 1: log into Jellyfin via Seerr → creates / authenticates
          # the mirror admin user in Seerr's DB.
          auth_url = f"http://{HOST}:{SEERR_PORT}/api/v1/auth/jellyfin"
          auth_body = {
              "username":   jf_user,
              "password":   jf_pwd,
              "email":      f"{jf_user}@local",
              "hostname":   HOST,
              "port":       JELLYFIN_PORT,
              "useSsl":     False,
              "urlBase":    "",
              "serverType": 2,  # 1 = Plex, 2 = Jellyfin (Jellyseerr convention)
          }
          try:
              urllib.request.urlopen(
                  urllib.request.Request(
                      auth_url,
                      data=json.dumps(auth_body).encode(),
                      headers={"Content-Type": "application/json"},
                      method="POST",
                  ),
                  timeout=30,
              ).read()
              log("seerr: /api/v1/auth/jellyfin succeeded (mirror admin set up)")
          except urllib.error.HTTPError as e:
              log(f"seerr: /api/v1/auth/jellyfin failed ({e.code}): {e.read()[:300]!r}. "
                  f"Verify Jellyfin is reachable at {HOST}:{JELLYFIN_PORT} and that "
                  "the seeded creds match a Jellyfin admin account.")
              return False
          except (urllib.error.URLError, TimeoutError, OSError) as e:
              log(f"seerr: cannot reach Seerr at {auth_url} ({e})")
              return False

          # Reload settings to pick up the apiKey that may have just been
          # generated, and to know whether /auth/jellyfin already flipped
          # initialized.
          try:
              api_key, initialized = extract_seerr_state()
          except Exception as e:
              log(f"seerr: post-auth state read failed — {e}")
              return False

          # Step 2: persist the Jellyfin connection (incl. external hostname).
          # `name` is read-only on Seerr's OpenAPI schema for this endpoint
          # — it's auto-derived from serverType. Sending it returns 400.
          settings_url = f"http://{HOST}:{SEERR_PORT}/api/v1/settings/jellyfin"
          settings_body = {
              "hostname":          HOST,
              "port":              JELLYFIN_PORT,
              "useSsl":            False,
              "urlBase":           "",
              "externalHostname":  JELLYFIN_EXTERNAL,
          }
          try:
              http("POST", settings_url, api_key, settings_body)
              log("seerr: Jellyfin connection settings persisted")
          except urllib.error.HTTPError as e:
              log(f"seerr: POST /api/v1/settings/jellyfin failed ({e.code}): {e.read()[:200]!r}")

          # Step 3: explicitly mark initialized (no-op if /auth/jellyfin
          # already did so).
          if not initialized:
              init_url = f"http://{HOST}:{SEERR_PORT}/api/v1/settings/initialize"
              try:
                  http("POST", init_url, api_key)
                  log("seerr: public.initialized set to true")
              except urllib.error.HTTPError as e:
                  log(f"seerr: POST /api/v1/settings/initialize failed ({e.code}): {e.read()[:200]!r}")

          return True


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
              log("seerr: wizard not yet completed — attempting auto-run from sops creds")
              reconcile_seerr_wizard()
              # Re-read; the wizard run above should have flipped initialized.
              try:
                  seerr_key, initialized = extract_seerr_state()
              except Exception as e:
                  log(f"seerr: post-wizard state read failed — {e}")
                  return

          if not initialized:
              log("seerr: still not initialized after wizard attempt; skipping *arr registration")
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
    # If the rendered env file changes (i.e. the admin password rotated),
    # restart the reconciler so it pushes the new password to all three
    # *arrs without needing `systemctl restart` by hand.
    restartUnits = ["media-bootstrap.service"];
  };

  # Jellyfin admin creds, used by the host-side reconciler to drive Seerr's
  # first-run wizard via /api/v1/auth/jellyfin. Optional: if either secret
  # is absent, the reconciler logs and skips (the wizard can still be done
  # manually in Seerr's web UI). Seed *after* completing Jellyfin's own
  # first-run wizard once — Jellyfin's setup API is version-fragile and not
  # worth automating, so we leave it as a single manual step and pair from
  # there.
  sops.secrets."media/jellyfin-admin-username" = {
    mode = "0400";
  };
  sops.secrets."media/jellyfin-admin-password" = {
    mode = "0400";
  };

  sops.templates."media-bootstrap-seerr-env" = {
    content = ''
      JELLYFIN_ADMIN_USERNAME=${config.sops.placeholder."media/jellyfin-admin-username"}
      JELLYFIN_ADMIN_PASSWORD=${config.sops.placeholder."media/jellyfin-admin-password"}
    '';
    mode = "0400";
    # Same idea as media-bootstrap-env: when the Jellyfin admin creds in
    # sops change (placeholders → real values, or rotated), `nixos-rebuild
    # switch` re-runs the reconciler. The wizard auto-run path is gated on
    # `initialized=false`, so on already-initialized stacks the restart is
    # a fast no-op apart from re-running the *arr registration loop.
    restartUnits = ["media-bootstrap-seerr.service"];
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
      EnvironmentFile = config.sops.templates."media-bootstrap-seerr-env".path;
      SuccessExitStatus = "0 1";
    };
  };
}
