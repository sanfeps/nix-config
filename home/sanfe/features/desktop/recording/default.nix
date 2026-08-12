# Screen-recording stack for content work (game-dev videos).
#
# Two tools with deliberately different jobs — they are not redundant:
#
#   - OBS Studio: composed, planned recordings. Scenes, split-screen
#     before/after comparisons, source cropping. Capture goes through the
#     PipeWire ScreenCast portal, which hosts/optional/xdg-portal.nix already
#     binds to the GNOME backend so it works under niri.
#
#   - gpu-screen-recorder: the always-on replay buffer ("save what just
#     happened", ShadowPlay-style). It uses the DRM/KMS capture path instead of
#     the portal — cheaper, and promptless. That path needs the setcap'd
#     gsr-kms-server helper, installed system-side by
#     `programs.gpu-screen-recorder.enable` in hosts/midgard/default.nix. The
#     `gpu-screen-recorder` binary therefore comes from PATH (the system
#     package, built with the right wrapperDir), NOT from a pkgs reference
#     here — a store-path reference would look for gsr-kms-server next to
#     itself, uncapped, and fall back to the portal.
#
# ffmpeg is not required by either to record (both bundle/link their own
# libraries). It is here as a CLI for post: trimming without re-encoding,
# concat, remux to a delivery container.
{pkgs, ...}: let
  # --- Replay buffer knobs ---------------------------------------------------
  replaySeconds = 60;
  fps = 60;

  # CBR + constant frame rate keeps RAM usage predictable (upstream's
  # recommendation for replay mode): the buffer costs roughly
  # bitrate/8 * replaySeconds ≈ 300 MB at these numbers.
  bitrateKbps = 40000;

  # HEVC is not a taste call here, it is a hard requirement: NVENC's H.264
  # encoder tops out at 4096 px wide and DP-1 is 5120 px. Leaving the default
  # (auto → h264) would fail to encode a full-screen capture.
  codec = "hevc";

  # What gets captured. "screen" = the whole 5120x1440 output; clips then get
  # framed to 16:9 at edit time. To have the replays come out already
  # YouTube-shaped instead, swap this for a centred 16:9 crop of the
  # ultrawide — no game-side changes needed, but anything outside the box
  # (corner HUD elements) is gone for good:
  #   captureArgs = ["-w" "region" "-region" "2560x1440+1280+0"];
  captureArgs = ["-w" "screen"];

  replayDir = "$HOME/Videos/Replays";

  # gpu-screen-recorder -sc hands the script the saved file path ($1) and the
  # kind of save ($2: regular|replay|screenshot).
  onSaved = pkgs.writeShellScript "gsr-replay-saved" ''
    ${pkgs.libnotify}/bin/notify-send -a gpu-screen-recorder \
      "Replay saved" "$(basename "$1")"
  '';

  # Track the daemon by PID file rather than by pkill pattern. Upstream
  # documents `pkill -f '^gpu-screen-recorder'`, but that is wrong on NixOS:
  # bin/gpu-screen-recorder is a makeWrapper shell script that execs
  # bin/.wrapped/gpu-screen-recorder by absolute path, so the running process's
  # argv[0] is a /nix/store path and the anchored pattern never matches. The
  # toggle then always fell through to "start", stacking up recorders.
  # The wrapper uses exec, so $$ below is the PID that actually receives signals.
  pidFile = "\${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/gsr-replay.pid";

  gsr-replay = pkgs.writeShellApplication {
    name = "gsr-replay";
    runtimeInputs = [pkgs.libnotify pkgs.coreutils];
    text = ''
      pidfile="${pidFile}"

      # Toggle off, but only if the recorded PID is still alive — a stale file
      # (crash, reboot) must not block starting a new buffer.
      if [[ -f "$pidfile" ]]; then
        pid=$(cat "$pidfile")
        if kill -0 "$pid" 2>/dev/null; then
          kill -INT "$pid"
          rm -f "$pidfile"
          notify-send -a gpu-screen-recorder "Replay buffer stopped"
          exit 0
        fi
        rm -f "$pidfile"
      fi

      mkdir -p "${replayDir}"
      notify-send -a gpu-screen-recorder \
        "Replay buffer running" "Last ${toString replaySeconds}s — Mod+Alt+S to save"

      # exec replaces this shell, so $$ stays valid for the recorder itself.
      echo $$ >"$pidfile"

      exec gpu-screen-recorder \
        ${builtins.concatStringsSep " " captureArgs} \
        -f ${toString fps} \
        -fm cfr \
        -k ${codec} \
        -bm cbr \
        -q ${toString bitrateKbps} \
        -a default_output \
        -c mp4 \
        -r ${toString replaySeconds} \
        -replay-storage ram \
        -df yes \
        -sc ${onSaved} \
        -o "${replayDir}"
    '';
  };

  gsr-save = pkgs.writeShellApplication {
    name = "gsr-save";
    runtimeInputs = [pkgs.libnotify pkgs.coreutils];
    text = ''
      pidfile="${pidFile}"

      if [[ -f "$pidfile" ]] && kill -0 "$(cat "$pidfile")" 2>/dev/null; then
        # SIGUSR1 dumps the buffer; the recorder keeps running afterwards.
        kill -USR1 "$(cat "$pidfile")"
        exit 0
      fi

      notify-send -a gpu-screen-recorder \
        "No replay buffer running" "Mod+Alt+R starts it"
      exit 1
    '';
  };
in {
  programs.obs-studio = {
    enable = true;
    plugins = with pkgs.obs-studio-plugins; [
      # Per-application audio sources over PipeWire, so game audio and mic land
      # on separate tracks and stay separable in the edit.
      obs-pipewire-audio-capture
      # Direct Vulkan/OpenGL game capture, bypassing the portal. Games have to
      # opt in by launching through `obs-gamecapture` (as a Steam launch option:
      # `obs-gamecapture %command%`).
      obs-vkcapture
    ];
  };

  home.packages = [
    # Post-production CLI. -full for NVENC plus the wider filter/codec set.
    pkgs.ffmpeg-full
    # Provides the `obs-gamecapture` launcher that feeds the plugin above.
    pkgs.obs-studio-plugins.obs-vkcapture
    gsr-replay
    gsr-save
  ];

  # Scene collections, profiles and encoder settings. midgard wipes / on boot,
  # so without this the whole OBS setup is gone every reboot. Recordings
  # themselves are fine — ~/Videos is already persisted in common/core.
  home.persistence."/persist".directories = [".config/obs-studio"];
}
