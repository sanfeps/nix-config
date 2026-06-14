#!/usr/bin/env python3
"""
yt2jelly-ui — browser frontend for yt2jellyd.

Usage:
  pip install flask
  export YOUTUBE_API_KEY=<your Google API key with YouTube Data API v3>
  export YT2JELLYD_URL=https://yt2jelly.lan.valgrindr.net   # or http://127.0.0.1:8398
  export YT2JELLYD_TOKEN=$(cat /var/lib/yt2jellyd/token)
  python app.py

Optional env vars:
  HOST   — bind address (default: 127.0.0.1)
  PORT   — bind port    (default: 5050)
"""

import json
import os
import re
import urllib.error
import urllib.parse
import urllib.request

from flask import Flask, jsonify, render_template, request

app = Flask(__name__)

YOUTUBE_API_KEY = os.environ.get("YOUTUBE_API_KEY", "")
YT2JELLYD_URL = os.environ.get("YT2JELLYD_URL", "http://127.0.0.1:8398").rstrip("/")
YT2JELLYD_TOKEN = os.environ.get("YT2JELLYD_TOKEN", "")


# ── YouTube helpers ────────────────────────────────────────────────────────────

def _yt_get(resource, params):
    params["key"] = YOUTUBE_API_KEY
    url = "https://www.googleapis.com/youtube/v3/" + resource + "?" + urllib.parse.urlencode(params)
    with urllib.request.urlopen(url, timeout=10) as resp:
        return json.loads(resp.read())


def _parse_iso_duration(iso):
    m = re.match(r"PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?", iso or "")
    if not m:
        return ""
    h, mins, s = (int(x or 0) for x in m.groups())
    return f"{h}:{mins:02d}:{s:02d}" if h else f"{mins}:{s:02d}"


# ── yt2jellyd proxy ───────────────────────────────────────────────────────────

def _jellyd(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    headers = {"Authorization": f"Bearer {YT2JELLYD_TOKEN}"}
    if data:
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(YT2JELLYD_URL + path, data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            return json.loads(resp.read()), resp.status
    except urllib.error.HTTPError as exc:
        return json.loads(exc.read()), exc.code


# ── Routes ────────────────────────────────────────────────────────────────────

@app.route("/")
def index():
    return render_template("index.html")


@app.route("/api/search")
def search():
    q = request.args.get("q", "").strip()
    if not q:
        return jsonify({"error": "empty query"}), 400
    if not YOUTUBE_API_KEY:
        return jsonify({"error": "YOUTUBE_API_KEY is not configured"}), 503

    try:
        search_data = _yt_get("search", {
            "part": "snippet",
            "type": "video",
            "maxResults": "10",
            "videoCategoryId": "10",  # Music category
            "q": q,
        })
    except (urllib.error.URLError, urllib.error.HTTPError) as exc:
        return jsonify({"error": f"YouTube API error: {exc}"}), 502

    items = search_data.get("items", [])
    if not items:
        return jsonify({"results": []})

    # Batch-fetch durations in a single call
    video_ids = ",".join(it["id"]["videoId"] for it in items)
    try:
        details = _yt_get("videos", {"part": "contentDetails", "id": video_ids})
        duration_map = {
            it["id"]: _parse_iso_duration(it["contentDetails"]["duration"])
            for it in details.get("items", [])
        }
    except (urllib.error.URLError, urllib.error.HTTPError):
        duration_map = {}

    results = []
    for it in items:
        vid = it["id"]["videoId"]
        s = it["snippet"]
        thumbs = s.get("thumbnails", {})
        thumb = (thumbs.get("medium") or thumbs.get("default") or {}).get("url", "")
        results.append({
            "id": vid,
            "url": f"https://www.youtube.com/watch?v={vid}",
            "title": s["title"],
            "channel": s["channelTitle"],
            "thumbnail": thumb,
            "duration": duration_map.get(vid, ""),
        })

    return jsonify({"results": results})


@app.route("/api/add", methods=["POST"])
def add():
    data = request.get_json(force=True) or {}
    url = (data.get("url") or "").strip()
    if not url:
        return jsonify({"error": "url is required"}), 400

    try:
        payload, status = _jellyd("POST", "/add", {
            "url": url,
            "artist": (data.get("artist") or "").strip(),
            "title": (data.get("title") or "").strip(),
        })
    except (urllib.error.URLError, OSError) as exc:
        return jsonify({"error": f"Cannot reach yt2jellyd: {exc}"}), 502

    return jsonify(payload), status


@app.route("/api/jobs")
def jobs():
    try:
        payload, status = _jellyd("GET", "/jobs")
    except (urllib.error.URLError, OSError) as exc:
        return jsonify({"error": f"Cannot reach yt2jellyd: {exc}"}), 502
    return jsonify(payload), status


if __name__ == "__main__":
    host = os.environ.get("HOST", "127.0.0.1")
    port = int(os.environ.get("PORT", "5050"))
    app.run(host=host, port=port)
