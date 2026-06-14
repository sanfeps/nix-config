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
#   - binds 127.0.0.1:5050, fronted by asgard's own Caddy at
#     music.lan.valgrindr.net. Needs the matching AdGuard rewrite in
#     hosts/bifrost/services/dns.nix (music -> asgard 192.168.1.54).
#
# Trust model: the UI itself is UNAUTHENTICATED on the LAN — it holds the token
# and exposes an open proxy, the same posture as the Flask PR and as the *arrs'
# local-address auth bypass. If you want a gate, add `basic_auth` to the Caddy
# vhost at the bottom; the backend stays loopback-only either way.
let
  indexHtml =
    pkgs.writeText "yt2jelly-ui-index.html"
    (builtins.readFile ./yt2jelly-ui.html);

  yt2jelly-ui = pkgs.writers.writePython3Bin "yt2jelly-ui" {
    # E501 long lines; W503/W504 line-break-around-operator (these two are
    # mutually exclusive and both in flake8's default ignore set anyway).
    flakeIgnore = ["E501" "W503" "W504"];
  } ''
    import http.server
    import json
    import os
    import re
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
            self.end_headers()
            self.wfile.write(raw)

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
  # media/youtube-api-key). Rendered into an EnvironmentFile for the service.
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
      YT2JELLY_UI_HOST = "127.0.0.1";
      YT2JELLY_UI_PORT = "5050";
      YT2JELLY_UI_INDEX = "${indexHtml}";
      YT2JELLYD_URL = "http://127.0.0.1:8398";
      YT2JELLYD_TOKEN_FILE = "/var/lib/yt2jellyd/token";
    };
    serviceConfig = {
      ExecStart = "${yt2jelly-ui}/bin/yt2jelly-ui";
      EnvironmentFile = config.sops.templates."yt2jelly-ui-env".path;
      # Same user as the daemon so it can read /var/lib/yt2jellyd/token.
      User = "yt2jelly";
      Group = "yt2jelly";
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
}
