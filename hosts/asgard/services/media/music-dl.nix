{
  config,
  pkgs,
  ...
}:
# yt2jelly — grab a song off YouTube straight into the Jellyfin music library,
# tagged as well as we reasonably can for free. Runs on asgard (where the
# library lives), so no scp round-trip.
#
# Design (after a long detour through beets/AcoustID and recognition APIs):
# there is no free + reliable acoustic-recognition path for arbitrary YouTube
# audio — AcoustID/Chromaprint (beets) misses YouTube rips, Shazam-grade APIs
# (AudD/ACRCloud) are paid, and shazamio is unpackaged/broken in nixpkgs. So we
# lean on the two free signals that DO work:
#   1. yt-dlp pulls YouTube's own structured music metadata when present
#      (artist/track/album — this is why "official" music videos tag cleanly).
#   2. A title parser ("Artist - Title") covers uploads where YouTube only gives
#      the uploader as artist (e.g. label-archive channels).
# We embed those tags + the thumbnail, file the track under $artist/Singles/
# $title, and let Jellyfin's own MusicBrainz/TheAudioDB providers enrich from
# there (which works well off correct artist/title). See media/CLAUDE.md.
#
# Not perfect: a video whose title is just "Song Name" with a label uploader
# will land under that uploader — that's the realistic ceiling for a free,
# zero-dependency tool. Fix such cases by renaming in Jellyfin, or pass tags
# explicitly (ARTIST=… TITLE=… yt2jelly …) — see below.
#
# Caveats:
#   - The invoking user must be in the `media` group (storage.nix backs the
#     library dir 0775 root:media); sanfe is added below. `sudo -E` also works.
let
  yt2jelly = pkgs.writeShellApplication {
    name = "yt2jelly";
    runtimeInputs = with pkgs; [
      yt-dlp
      ffmpeg # also provides ffprobe (read back the embedded tags)
      atomicparsley # yt-dlp uses it to embed thumbnails into m4a containers
    ];
    text = ''
      MUSIC_LIB="''${MUSIC_LIB:-/mnt/nas/media/library/music}"
      AUDIO_FORMAT="''${AUDIO_FORMAT:-mp3}"

      if [ "$#" -eq 0 ]; then
        echo "usage: yt2jelly <youtube-url> [more-urls...]" >&2
        echo "  env: MUSIC_LIB (default $MUSIC_LIB), AUDIO_FORMAT (mp3)," >&2
        echo "       ARTIST/TITLE (override the auto-detected tags)" >&2
        exit 2
      fi

      if [ ! -w "$MUSIC_LIB" ]; then
        echo "error: $MUSIC_LIB not writable by $(id -un)." >&2
        echo "       add your user to the 'media' group, or run: sudo -E yt2jelly ..." >&2
        exit 1
      fi

      STAGE="$(mktemp -d -t yt2jelly.XXXXXX)"
      trap 'rm -rf "$STAGE"' EXIT

      for url in "$@"; do
        rm -f "$STAGE"/in.*

        # Best-quality audio + thumbnail. --parse-metadata derives artist/title
        # from an "Artist - Title" video title, overriding YouTube's
        # uploader-as-artist; for titles YT already tagged (music videos) it's a
        # no-op and the real metadata is kept. --embed-metadata writes it all in.
        yt-dlp \
          -x --audio-format "$AUDIO_FORMAT" --audio-quality 0 \
          --embed-thumbnail --embed-metadata --no-playlist \
          --parse-metadata "title:%(artist)s - %(title)s" \
          -o "$STAGE/in.%(ext)s" "$url"
        f="$STAGE/in.$AUDIO_FORMAT"

        # Tags for the on-disk layout: explicit env overrides win, else read
        # back what yt-dlp embedded.
        artist="''${ARTIST:-}"
        title="''${TITLE:-}"
        [ -n "$artist" ] || artist="$(ffprobe -v quiet -show_entries format_tags=artist -of default=nw=1:nk=1 "$f" || true)"
        [ -n "$title" ] || title="$(ffprobe -v quiet -show_entries format_tags=title -of default=nw=1:nk=1 "$f" || true)"
        [ -n "$artist" ] || artist="Unknown Artist"
        [ -n "$title" ] || title="$(basename "$f" ".$AUDIO_FORMAT")"

        # If env overrides were given, write them back into the file too.
        if [ -n "''${ARTIST:-}" ] || [ -n "''${TITLE:-}" ]; then
          tagged="$STAGE/tagged.$AUDIO_FORMAT"
          args=(-y -v error -i "$f" -map 0 -c copy -metadata "artist=$artist" -metadata "title=$title")
          ffmpeg "''${args[@]}" "$tagged"
          f="$tagged"
        fi

        # File it: $artist/Singles/$title (slashes neutralised so they can't
        # escape the layout).
        artist_dir="''${artist//\//-}"
        title_file="''${title//\//-}"
        dest="$MUSIC_LIB/$artist_dir/Singles"
        mkdir -p "$dest"
        mv -f "$f" "$dest/$title_file.$AUDIO_FORMAT"
        echo "→ $dest/$title_file.$AUDIO_FORMAT  ($artist - $title)"
      done

      echo "done — rescan the Music library in Jellyfin"
    '';
  };

  yt2jellyd = pkgs.writers.writePython3Bin "yt2jellyd" {} ''
    import http.server
    import json
    import os
    import secrets
    import subprocess
    import threading
    import time
    import urllib.error
    import urllib.parse
    import urllib.request

    HOST = os.environ.get("YT2JELLYD_HOST", "127.0.0.1")
    PORT = int(os.environ.get("YT2JELLYD_PORT", "8398"))
    TOKEN_FILE = os.environ.get("YT2JELLYD_TOKEN_FILE", "/var/lib/yt2jellyd/token")
    YT2JELLY_BIN = os.environ.get("YT2JELLY_BIN", "yt2jelly")
    MUSIC_LIB = os.environ.get("MUSIC_LIB", "/mnt/nas/media/library/music")
    AUDIO_FORMAT = os.environ.get("AUDIO_FORMAT", "mp3")
    JELLYFIN_URL = os.environ.get("JELLYFIN_URL", "http://127.0.0.1:8096")
    JELLYFIN_API_KEY_FILE = os.environ.get("JELLYFIN_API_KEY_FILE", "")
    JELLYFIN_ADMIN_USERNAME = os.environ.get("JELLYFIN_ADMIN_USERNAME", "")
    JELLYFIN_ADMIN_PASSWORD = os.environ.get("JELLYFIN_ADMIN_PASSWORD", "")

    lock = threading.Lock()
    jobs = {}
    job_counter = 0


    def load_or_create_token():
        os.makedirs(os.path.dirname(TOKEN_FILE), mode=0o700, exist_ok=True)
        if not os.path.exists(TOKEN_FILE):
            token = secrets.token_urlsafe(32)
            fd = os.open(TOKEN_FILE, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            with os.fdopen(fd, "w") as f:
                f.write(token + "\n")
        with open(TOKEN_FILE) as f:
            return f.read().strip()


    TOKEN = load_or_create_token()


    def read_body(handler):
        length = int(handler.headers.get("content-length", "0"))
        if length <= 0:
            return {}
        raw = handler.rfile.read(length).decode("utf-8").strip()
        content_type = handler.headers.get("content-type", "")
        if "application/json" in content_type:
            return json.loads(raw)
        if "application/x-www-form-urlencoded" in content_type:
            data = urllib.parse.parse_qs(raw)
            return {k: v[-1] for k, v in data.items()}
        return {"url": raw}


    def is_allowed_url(url):
        try:
            parsed = urllib.parse.urlparse(url)
        except ValueError:
            return False
        if parsed.scheme not in ("http", "https"):
            return False
        host = (parsed.hostname or "").lower()
        return host in {
            "youtube.com",
            "www.youtube.com",
            "music.youtube.com",
            "youtu.be",
        }


    def jellyfin_refresh():
        token = ""
        if not JELLYFIN_API_KEY_FILE or not os.path.exists(JELLYFIN_API_KEY_FILE):
            if not JELLYFIN_ADMIN_USERNAME or not JELLYFIN_ADMIN_PASSWORD:
                return "skipped"
            auth_url = JELLYFIN_URL.rstrip("/") + "/Users/AuthenticateByName"
            auth_body = json.dumps({
                "Username": JELLYFIN_ADMIN_USERNAME,
                "Pw": JELLYFIN_ADMIN_PASSWORD,
            }).encode("utf-8")
            auth_request = urllib.request.Request(
                auth_url,
                data=auth_body,
                method="POST",
                headers={
                    "Content-Type": "application/json",
                    "X-Emby-Authorization": (
                        'MediaBrowser Client="yt2jellyd", '
                        'Device="asgard", DeviceId="yt2jellyd", Version="1"'
                    ),
                },
            )
            with urllib.request.urlopen(auth_request, timeout=15) as response:
                payload = json.loads(response.read().decode("utf-8"))
                token = payload.get("AccessToken", "")
        else:
            with open(JELLYFIN_API_KEY_FILE) as f:
                token = f.read().strip()

        if not token:
            return "skipped"
        url = JELLYFIN_URL.rstrip("/") + "/Library/Refresh"
        request = urllib.request.Request(
            url,
            method="POST",
            headers={"X-Emby-Token": token},
        )
        with urllib.request.urlopen(request, timeout=15) as response:
            return "requested:" + str(response.status)


    def run_job(job_id, url, artist, title):
        env = os.environ.copy()
        env.update({
            "MUSIC_LIB": MUSIC_LIB,
            "AUDIO_FORMAT": AUDIO_FORMAT,
        })
        if artist:
            env["ARTIST"] = artist
        if title:
            env["TITLE"] = title

        with lock:
            jobs[job_id].update({"status": "running", "started_at": time.time()})

        command = [YT2JELLY_BIN, url]
        proc = subprocess.run(command, env=env, text=True, capture_output=True)
        refresh = "skipped"
        if proc.returncode == 0:
            try:
                refresh = jellyfin_refresh()
            except (OSError, urllib.error.URLError) as exc:
                refresh = "failed:" + str(exc)

        with lock:
            jobs[job_id].update({
                "status": "done" if proc.returncode == 0 else "failed",
                "finished_at": time.time(),
                "returncode": proc.returncode,
                "stdout": proc.stdout[-4000:],
                "stderr": proc.stderr[-4000:],
                "jellyfin_refresh": refresh,
            })


    class Handler(http.server.BaseHTTPRequestHandler):
        def log_message(self, fmt, *args):
            print("%s - %s" % (self.address_string(), fmt % args), flush=True)

        def send_json(self, status, payload):
            body = json.dumps(payload, indent=2).encode("utf-8")
            self.send_response(status)
            self.send_header("content-type", "application/json")
            self.send_header("content-length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def authenticated(self):
            header = self.headers.get("authorization", "")
            token = self.headers.get("x-yt2jelly-token", "")
            if header.lower().startswith("bearer "):
                token = header[7:].strip()
            return secrets.compare_digest(token, TOKEN)

        def do_GET(self):
            if self.path == "/health":
                self.send_json(200, {"ok": True})
                return
            if not self.authenticated():
                self.send_json(401, {"error": "missing or invalid token"})
                return
            if self.path == "/jobs":
                with lock:
                    payload = {"jobs": list(reversed(list(jobs.values())))[0:25]}
                self.send_json(200, payload)
                return
            self.send_json(404, {"error": "not found"})

        def do_POST(self):
            global job_counter
            if not self.authenticated():
                self.send_json(401, {"error": "missing or invalid token"})
                return
            if self.path != "/add":
                self.send_json(404, {"error": "not found"})
                return
            try:
                data = read_body(self)
            except (json.JSONDecodeError, UnicodeDecodeError):
                self.send_json(400, {"error": "invalid request body"})
                return
            url = (data.get("url") or "").strip()
            artist = (data.get("artist") or "").strip()
            title = (data.get("title") or "").strip()
            if not is_allowed_url(url):
                self.send_json(400, {"error": "expected a YouTube URL"})
                return

            with lock:
                job_counter += 1
                job_id = str(job_counter)
                jobs[job_id] = {
                    "id": job_id,
                    "url": url,
                    "artist": artist,
                    "title": title,
                    "status": "queued",
                    "queued_at": time.time(),
                }

            thread = threading.Thread(
                target=run_job,
                args=(job_id, url, artist, title),
                daemon=True,
            )
            thread.start()
            self.send_json(202, {"job": jobs[job_id]})


    if __name__ == "__main__":
        server = http.server.ThreadingHTTPServer((HOST, PORT), Handler)
        print("yt2jellyd listening on %s:%d" % (HOST, PORT), flush=True)
        server.serve_forever()
  '';
in {
  environment.systemPackages = [
    yt2jelly
    yt2jellyd
  ];

  users.users.yt2jelly = {
    isSystemUser = true;
    group = "yt2jelly";
    extraGroups = ["media"];
  };
  users.groups.yt2jelly = {};

  sops.templates."yt2jellyd-env" = {
    content = ''
      JELLYFIN_ADMIN_USERNAME=${config.sops.placeholder."media/jellyfin-admin-username"}
      JELLYFIN_ADMIN_PASSWORD=${config.sops.placeholder."media/jellyfin-admin-password"}
    '';
    owner = "yt2jelly";
    mode = "0400";
    restartUnits = ["yt2jellyd.service"];
  };

  systemd.services.yt2jellyd = {
    description = "Phone-friendly HTTP wrapper for yt2jelly";
    wantedBy = ["multi-user.target"];
    after = ["network-online.target" "jellyfin.service"];
    wants = ["network-online.target"];
    environment = {
      YT2JELLY_BIN = "${yt2jelly}/bin/yt2jelly";
      YT2JELLYD_HOST = "127.0.0.1";
      YT2JELLYD_PORT = "8398";
      YT2JELLYD_TOKEN_FILE = "/var/lib/yt2jellyd/token";
      MUSIC_LIB = "/mnt/nas/media/library/music";
      AUDIO_FORMAT = "mp3";
      JELLYFIN_URL = "http://127.0.0.1:8096";
      HOME = "/var/lib/yt2jellyd";
      XDG_CACHE_HOME = "/var/lib/yt2jellyd/cache";
      XDG_CONFIG_HOME = "/var/lib/yt2jellyd/config";
    };
    serviceConfig = {
      ExecStart = "${yt2jellyd}/bin/yt2jellyd";
      EnvironmentFile = config.sops.templates."yt2jellyd-env".path;
      User = "yt2jelly";
      Group = "yt2jelly";
      StateDirectory = "yt2jellyd";
      StateDirectoryMode = "0700";
      Restart = "on-failure";
      RestartSec = "10s";
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      ReadWritePaths = [
        "/mnt/nas/media/library/music"
        "/var/lib/yt2jellyd"
      ];
    };
  };

  services.caddy.virtualHosts."yt2jelly.lan.valgrindr.net".extraConfig = ''
    reverse_proxy 127.0.0.1:8398
  '';

  environment.persistence."${config.hostSpec.persistFolder}".directories = [
    {
      directory = "/var/lib/yt2jellyd";
      user = "yt2jelly";
      group = "yt2jelly";
      mode = "0700";
    }
  ];

  # yt2jelly writes into the media-group-owned library dir (0775 root:media),
  # so the invoking user needs to be in that group.
  users.users.${config.hostSpec.username}.extraGroups = ["media"];
}
