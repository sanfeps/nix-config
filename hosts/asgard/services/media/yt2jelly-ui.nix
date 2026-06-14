{
  config,
  pkgs,
  ...
}:
# yt2jelly-ui — browser frontend for yt2jellyd (search YouTube, play the result
# in-page, add it to Jellyfin). This is the Nixified counterpart to the
# tools/yt2jelly-ui Flask PR (#1), folded into the media stack the repo way:
#
#   - stdlib http.server, NOT Flask. The page (./yt2jelly-ui.html) is fully
#     static — it uses no template variables — so Flask's template engine was
#     dead weight. Packaged with writePython3Bin, matching the yt2jellyd daemon
#     next door (music-dl.nix); no requirements.txt, no pip.
#   - runs as the SAME `yt2jelly` system user as the daemon, so it can read the
#     auto-generated bearer token at /var/lib/yt2jellyd/token and proxy /add and
#     /jobs over loopback. No token duplicated into sops.
#   - the YouTube Data API key comes from sops (`media/youtube-api-key`) via an
#     EnvironmentFile, exactly like the jellyfin-admin creds in music-dl.nix.
#   - GET /api/stream?id=<videoId> proxies the track's audio for background
#     playback: the 🎧 Listen button in the page feeds it to an <audio> element
#     the browser owns (with Media Session metadata), so it keeps playing with
#     the screen off / browser backgrounded — which a YouTube <iframe> embed
#     refuses to do. asgard resolves the direct audio URL with yt-dlp (`-g`) and
#     proxies the bytes, forwarding Range so seeking works. The URL is cached
#     (and pre-warmed on card open / first result) to hide the resolve latency.
#     The YouTube embed (📺 Video) stays as a foreground-only preview.
#   - binds 0.0.0.0:5050; on the LAN only loopback (Caddy) reaches it (no LAN
#     firewall hole) and it's fronted at music.lan.valgrindr.net — needs the
#     AdGuard rewrite in hosts/bifrost/services/dns.nix (music -> 192.168.1.54).
#   - tailnet guests reach it directly at http://asgard.ts.yggdrasil.lo:5050
#     (:5050 opened on tailscale0 only), gated by the headscale ACL
#     (group:guest -> asgard:5050). Same exposure pattern as jellyfin.nix.
#
# Trust model: the UI is UNAUTHENTICATED — it holds the token and exposes an open
# proxy. On the LAN that's the same posture as the *arrs' local-address bypass;
# on the tailnet, access is gated by the headscale ACL (only enrolled guests).
# So a guest with the UI can search YouTube (your API quota) and add songs to the
# shared Jellyfin library — intended for trusted family/guests. If you want a
# gate anyway, add `basic_auth` to the Caddy vhost (LAN side only).
let
  indexHtml =
    pkgs.writeText "yt2jelly-ui-index.html"
    (builtins.readFile ./yt2jelly-ui.html);

  yt2jelly-ui =
    pkgs.writers.writePython3Bin "yt2jelly-ui" {
      # E501 long lines; W503/W504 line-break-around-operator (these two are
      # mutually exclusive and both in flake8's default ignore set anyway).
      flakeIgnore = ["E501" "W503" "W504"];
    } ''
      import http.server
      import json
      import os
      import re
      import subprocess
      import threading
      import time
      import urllib.error
      import urllib.parse
      import urllib.request

      HOST = os.environ.get("YT2JELLY_UI_HOST", "127.0.0.1")
      PORT = int(os.environ.get("YT2JELLY_UI_PORT", "5050"))
      INDEX_HTML = os.environ.get("YT2JELLY_UI_INDEX", "")
      YT2JELLYD_URL = os.environ.get("YT2JELLYD_URL", "http://127.0.0.1:8398").rstrip("/")
      YOUTUBE_API_KEY = os.environ.get("YOUTUBE_API_KEY", "")
      TOKEN_FILE = os.environ.get("YT2JELLYD_TOKEN_FILE", "/var/lib/yt2jellyd/token")

      PAGE = ""
      if INDEX_HTML:
          with open(INDEX_HTML) as fh:
              PAGE = fh.read()


      def load_token():
          try:
              with open(TOKEN_FILE) as fh:
                  return fh.read().strip()
          except OSError:
              return ""


      # YouTube Data API v3 helpers ───────────────────────────────────────────

      def yt_get(resource, params):
          params = dict(params)
          params["key"] = YOUTUBE_API_KEY
          url = ("https://www.googleapis.com/youtube/v3/"
                 + resource + "?" + urllib.parse.urlencode(params))
          with urllib.request.urlopen(url, timeout=10) as resp:
              return json.loads(resp.read())


      def parse_iso_duration(iso):
          m = re.match(r"PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?", iso or "")
          if not m:
              return ""
          h, mins, s = (int(x or 0) for x in m.groups())
          return "%d:%02d:%02d" % (h, mins, s) if h else "%d:%02d" % (mins, s)


      def youtube_search(q):
          data = yt_get("search", {
              "part": "snippet",
              "type": "video",
              "maxResults": "10",
              "videoCategoryId": "10",  # Music
              "q": q,
          })
          items = data.get("items", [])
          if not items:
              return []
          ids = ",".join(it["id"]["videoId"] for it in items)
          durations = {}
          try:
              det = yt_get("videos", {"part": "contentDetails", "id": ids})
              durations = {
                  it["id"]: parse_iso_duration(it["contentDetails"]["duration"])
                  for it in det.get("items", [])
              }
          except (urllib.error.URLError, urllib.error.HTTPError, KeyError):
              durations = {}
          results = []
          for it in items:
              vid = it["id"]["videoId"]
              snip = it["snippet"]
              thumbs = snip.get("thumbnails", {})
              thumb = (thumbs.get("medium") or thumbs.get("default") or {}).get("url", "")
              results.append({
                  "id": vid,
                  "url": "https://www.youtube.com/watch?v=" + vid,
                  "title": snip["title"],
                  "channel": snip["channelTitle"],
                  "thumbnail": thumb,
                  "duration": durations.get(vid, ""),
              })
          return results


      # yt2jellyd proxy ───────────────────────────────────────────────────────

      def jellyd(method, path, body=None):
          data = json.dumps(body).encode() if body is not None else None
          headers = {"Authorization": "Bearer " + load_token()}
          if data:
              headers["Content-Type"] = "application/json"
          req = urllib.request.Request(
              YT2JELLYD_URL + path, data=data, method=method, headers=headers)
          try:
              with urllib.request.urlopen(req, timeout=15) as resp:
                  return resp.status, json.loads(resp.read())
          except urllib.error.HTTPError as exc:
              try:
                  payload = json.loads(exc.read())
              except (ValueError, OSError):
                  payload = {"error": "yt2jellyd HTTP %d" % exc.code}
              return exc.code, payload


      # Audio streaming for background playback ────────────────────────────────
      # The browser plays this via an <audio> element it owns (NOT the YouTube
      # embed), which is what lets it keep playing with the screen off. asgard
      # resolves the direct audio URL with yt-dlp and proxies the bytes, so the
      # fetch always comes from asgard's IP (googlevideo URLs are tied to the
      # resolving client) regardless of where the phone is. Range requests are
      # forwarded upstream and the 206/Content-Range echoed back, so seeking works.

      YT_DLP_BIN = os.environ.get("YT_DLP_BIN", "yt-dlp")
      VIDEO_ID_RE = re.compile(r"^[A-Za-z0-9_-]{11}$")
      URL_TTL = 3 * 3600  # googlevideo URLs live ~6h; refresh well before expiry
      URL_CACHE_MAX = 256  # hard cap so the in-memory URL map can't grow forever
      _url_cache = {}      # video_id -> (direct_url, content_type, fetched_at)
      _url_cache_lock = threading.Lock()


      def _content_type_for(url):
          qs = urllib.parse.parse_qs(urllib.parse.urlparse(url).query)
          mime = qs.get("mime", [""])[0]
          return mime if mime.startswith("audio/") else "audio/mp4"


      def _cache_put(video_id, url, ctype, now):
          # Bound the cache: drop expired entries, then evict the oldest if still
          # over the cap. Entries are tiny (a URL string), so the cap is generous.
          with _url_cache_lock:
              for k in [k for k, v in _url_cache.items() if now - v[2] >= URL_TTL]:
                  del _url_cache[k]
              if len(_url_cache) >= URL_CACHE_MAX:
                  ordered = sorted(_url_cache, key=lambda k: _url_cache[k][2])
                  for k in ordered[:len(_url_cache) - URL_CACHE_MAX + 1]:
                      del _url_cache[k]
              _url_cache[video_id] = (url, ctype, now)


      def resolve_audio(video_id, force=False):
          now = time.time()
          if not force:
              with _url_cache_lock:
                  hit = _url_cache.get(video_id)
                  if hit and now - hit[2] < URL_TTL:
                      return hit[0], hit[1]
          # No --no-cache-dir: yt-dlp keeps its small player-signature cache under
          # $XDG_CACHE_HOME (set to the service's StateDirectory), so repeat
          # resolves skip re-downloading and re-running YouTube's player JS.
          proc = subprocess.run(
              [YT_DLP_BIN, "-f", "bestaudio[ext=m4a]/bestaudio",
               "-g", "--no-playlist", "--no-warnings",
               "--", video_id],
              capture_output=True, text=True, timeout=45)
          if proc.returncode != 0:
              raise RuntimeError(proc.stderr.strip() or "yt-dlp failed")
          lines = [ln.strip() for ln in proc.stdout.splitlines() if ln.strip()]
          if not lines:
              raise RuntimeError("yt-dlp returned no URL")
          url = lines[0]
          ctype = _content_type_for(url)
          _cache_put(video_id, url, ctype, now)
          return url, ctype


      class Handler(http.server.BaseHTTPRequestHandler):
          def log_message(self, fmt, *args):
              print("%s - %s" % (self.address_string(), fmt % args), flush=True)

          def send_json(self, status, payload):
              body = json.dumps(payload).encode()
              self.send_response(status)
              self.send_header("content-type", "application/json")
              self.send_header("content-length", str(len(body)))
              self.end_headers()
              self.wfile.write(body)

          def send_html(self, page):
              raw = page.encode()
              self.send_response(200)
              self.send_header("content-type", "text/html; charset=utf-8")
              self.send_header("content-length", str(len(raw)))
              # Don't let the browser serve a stale page after a redeploy — the
              # HTML is small and changes often during iteration.
              self.send_header("cache-control", "no-cache")
              self.end_headers()
              self.wfile.write(raw)

          def stream_audio(self, video_id):
              try:
                  url, ctype = resolve_audio(video_id)
              except Exception as exc:  # noqa: BLE001 - report any resolve failure
                  self.send_json(502, {"error": "resolve failed: %s" % exc})
                  return

              rng = self.headers.get("Range")
              upstream = None
              for attempt in (0, 1):
                  headers = {"User-Agent": "Mozilla/5.0"}
                  if rng:
                      headers["Range"] = rng
                  try:
                      upstream = urllib.request.urlopen(
                          urllib.request.Request(url, headers=headers), timeout=20)
                      break
                  except urllib.error.HTTPError as exc:
                      # 403/410 usually means the resolved URL expired — re-resolve
                      # once and retry before giving up.
                      if exc.code in (403, 410) and attempt == 0:
                          try:
                              url, ctype = resolve_audio(video_id, force=True)
                          except Exception:  # noqa: BLE001
                              self.send_json(502, {"error": "re-resolve failed"})
                              return
                          continue
                      self.send_json(502, {"error": "upstream HTTP %d" % exc.code})
                      return
                  except (urllib.error.URLError, OSError) as exc:
                      self.send_json(502, {"error": "upstream error: %s" % exc})
                      return

              try:
                  self.send_response(upstream.status)
                  self.send_header("content-type", ctype)
                  self.send_header("accept-ranges", "bytes")
                  clen = upstream.headers.get("Content-Length")
                  if clen:
                      self.send_header("content-length", clen)
                  crange = upstream.headers.get("Content-Range")
                  if crange:
                      self.send_header("content-range", crange)
                  self.send_header("cache-control", "no-store")
                  self.end_headers()
                  while True:
                      chunk = upstream.read(65536)
                      if not chunk:
                          break
                      self.wfile.write(chunk)
              except (BrokenPipeError, ConnectionResetError):
                  pass  # client seeked or navigated away — expected
              finally:
                  upstream.close()

          def do_GET(self):
              parsed = urllib.parse.urlparse(self.path)
              if parsed.path in ("/", "/index.html"):
                  self.send_html(PAGE)
                  return
              if parsed.path == "/health":
                  self.send_json(200, {"ok": True})
                  return
              if parsed.path == "/api/search":
                  qs = urllib.parse.parse_qs(parsed.query)
                  q = (qs.get("q", [""])[0]).strip()
                  if not q:
                      self.send_json(400, {"error": "empty query"})
                      return
                  if not YOUTUBE_API_KEY:
                      self.send_json(503, {"error": "YOUTUBE_API_KEY is not configured"})
                      return
                  try:
                      self.send_json(200, {"results": youtube_search(q)})
                  except (urllib.error.URLError, urllib.error.HTTPError) as exc:
                      self.send_json(502, {"error": "YouTube API error: %s" % exc})
                  return
              if parsed.path == "/api/jobs":
                  status, payload = jellyd("GET", "/jobs")
                  self.send_json(status, payload)
                  return
              if parsed.path == "/api/stream":
                  qs = urllib.parse.parse_qs(parsed.query)
                  vid = (qs.get("id", [""])[0]).strip()
                  if not VIDEO_ID_RE.match(vid):
                      self.send_json(400, {"error": "invalid id"})
                      return
                  self.stream_audio(vid)
                  return
              if parsed.path == "/api/resolve":
                  # Pre-warm: resolve (and cache) the audio URL without streaming,
                  # so a later /api/stream for the same id starts near-instantly.
                  qs = urllib.parse.parse_qs(parsed.query)
                  vid = (qs.get("id", [""])[0]).strip()
                  if not VIDEO_ID_RE.match(vid):
                      self.send_json(400, {"error": "invalid id"})
                      return
                  try:
                      resolve_audio(vid)
                      self.send_json(200, {"ok": True})
                  except Exception as exc:  # noqa: BLE001
                      self.send_json(502, {"error": "resolve failed: %s" % exc})
                  return
              self.send_json(404, {"error": "not found"})

          def do_POST(self):
              parsed = urllib.parse.urlparse(self.path)
              if parsed.path != "/api/add":
                  self.send_json(404, {"error": "not found"})
                  return
              length = int(self.headers.get("content-length", "0"))
              raw = self.rfile.read(length) if length > 0 else b"{}"
              try:
                  data = json.loads(raw or b"{}")
              except ValueError:
                  self.send_json(400, {"error": "invalid JSON"})
                  return
              url = (data.get("url") or "").strip()
              if not url:
                  self.send_json(400, {"error": "url is required"})
                  return
              body = {
                  "url": url,
                  "artist": (data.get("artist") or "").strip(),
                  "title": (data.get("title") or "").strip(),
                  "album": (data.get("album") or "").strip(),
              }
              try:
                  status, payload = jellyd("POST", "/add", body)
              except (urllib.error.URLError, OSError) as exc:
                  self.send_json(502, {"error": "cannot reach yt2jellyd: %s" % exc})
                  return
              self.send_json(status, payload)


      if __name__ == "__main__":
          server = http.server.ThreadingHTTPServer((HOST, PORT), Handler)
          print("yt2jelly-ui listening on %s:%d" % (HOST, PORT), flush=True)
          server.serve_forever()
    '';
in {
  environment.systemPackages = [yt2jelly-ui];

  # YouTube Data API key (add it with: sops hosts/asgard/secrets.yaml ->
  # media/youtube-api-key). Declared so the placeholder below resolves, then
  # rendered into an EnvironmentFile for the service.
  sops.secrets."media/youtube-api-key" = {
    mode = "0400";
  };

  sops.templates."yt2jelly-ui-env" = {
    content = ''
      YOUTUBE_API_KEY=${config.sops.placeholder."media/youtube-api-key"}
    '';
    owner = "yt2jelly";
    mode = "0400";
    restartUnits = ["yt2jelly-ui.service"];
  };

  systemd.services.yt2jelly-ui = {
    description = "Browser frontend for yt2jellyd (YouTube search -> Jellyfin)";
    wantedBy = ["multi-user.target"];
    after = ["network-online.target" "yt2jellyd.service"];
    wants = ["network-online.target"];
    environment = {
      # 0.0.0.0 so the tailscale0 firewall hole below can reach it; no LAN hole
      # is opened, so on the LAN only loopback (Caddy) gets in. Same pattern as
      # jellyfin.nix's tailnet guest exposure.
      YT2JELLY_UI_HOST = "0.0.0.0";
      YT2JELLY_UI_PORT = "5050";
      YT2JELLY_UI_INDEX = "${indexHtml}";
      YT2JELLYD_URL = "http://127.0.0.1:8398";
      YT2JELLYD_TOKEN_FILE = "/var/lib/yt2jellyd/token";
      # Used by /api/{stream,resolve} to resolve the direct audio URL for
      # background playback (the 🎧 Listen button).
      YT_DLP_BIN = "${pkgs.yt-dlp}/bin/yt-dlp";
      # yt-dlp's player-signature cache lives here (StateDirectory below), so
      # repeat resolves skip re-fetching/re-running YouTube's player JS. This is
      # small JSON keyed by player version, NOT audio — it does not grow large.
      XDG_CACHE_HOME = "/var/lib/yt2jelly-ui";
    };
    serviceConfig = {
      ExecStart = "${yt2jelly-ui}/bin/yt2jelly-ui";
      EnvironmentFile = config.sops.templates."yt2jelly-ui-env".path;
      # Same user as the daemon so it can read /var/lib/yt2jellyd/token.
      User = "yt2jelly";
      Group = "yt2jelly";
      # Writable dir for yt-dlp's player-signature cache (XDG_CACHE_HOME above).
      # ProtectSystem=strict otherwise makes the whole fs read-only.
      StateDirectory = "yt2jelly-ui";
      Restart = "on-failure";
      RestartSec = "10s";
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
    };
  };

  # Per-host Caddy: asgard fronts the UI itself. Pair with the AdGuard rewrite
  # `music.lan.valgrindr.net` -> 192.168.1.54 in hosts/bifrost/services/dns.nix.
  services.caddy.virtualHosts."music.lan.valgrindr.net".extraConfig = ''
    reverse_proxy 127.0.0.1:5050
  '';

  # Tailnet guest access (same pattern as jellyfin.nix :8096): open :5050 on the
  # tailscale0 interface only — NOT the LAN. Tailnet peers reach the UI directly
  # over the WireGuard-encrypted link (http://asgard.ts.yggdrasil.lo:5050). WHICH
  # peers is gated by the headscale ACL (group:guest -> asgard:5050 in
  # hosts/bifrost/services/headscale.nix), not by this rule. No TLS: the tailnet
  # link is already encrypted.
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [5050];
}
