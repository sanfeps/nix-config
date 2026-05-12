#!/usr/bin/env bash
# Voice assistant: hotkey toggles between recording mic and sending the
# transcription to Claude Code, then speaks the reply. Claude Code can take
# real actions on the system (read/edit files, run commands) without prompts.
set -euo pipefail

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/voice-assistant"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/voice-assistant"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/voice-assistant"
WORKSPACE_DIR="$STATE_DIR/workspace"
mkdir -p "$STATE_DIR" "$CACHE_DIR" "$DATA_DIR" "$WORKSPACE_DIR"

PID_FILE="$STATE_DIR/recording.pid"
AUDIO_FILE="$STATE_DIR/recording.wav"
LOG_FILE="$STATE_DIR/voice-assistant.log"

WHISPER_MODEL_NAME="ggml-medium.en.bin"
WHISPER_MODEL="$CACHE_DIR/$WHISPER_MODEL_NAME"
WHISPER_MODEL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$WHISPER_MODEL_NAME"

PIPER_VOICE="en_US-amy-medium"
PIPER_ONNX="$CACHE_DIR/${PIPER_VOICE}.onnx"
PIPER_JSON="$CACHE_DIR/${PIPER_VOICE}.onnx.json"
PIPER_BASE_URL="https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/amy/medium"

CLAUDE_MODEL="${VOICE_ASSISTANT_MODEL:-sonnet}"
VOICE_SYSTEM_PROMPT='You are responding through a voice assistant. Reply in plain spoken prose — no markdown, no bullet points, no code blocks. Keep answers to one or two short sentences unless the user explicitly asks for detail. When the user asks you to take an action on the system (edit files, run commands), do it and then confirm in one sentence what you did.'

log() { printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*" >> "$LOG_FILE"; }
notify() { notify-send -a "voice-assistant" -t "${2:-3000}" "Voice assistant" "$1" || true; }

ensure_models() {
  if [[ ! -s "$WHISPER_MODEL" ]]; then
    notify "Downloading Whisper model (~1.5GB, one time)…" 10000
    curl -fL --retry 3 -o "$WHISPER_MODEL.part" "$WHISPER_MODEL_URL"
    mv "$WHISPER_MODEL.part" "$WHISPER_MODEL"
  fi
  if [[ ! -s "$PIPER_ONNX" ]]; then
    notify "Downloading Piper voice…" 5000
    curl -fL --retry 3 -o "$PIPER_ONNX.part" "$PIPER_BASE_URL/${PIPER_VOICE}.onnx"
    mv "$PIPER_ONNX.part" "$PIPER_ONNX"
  fi
  if [[ ! -s "$PIPER_JSON" ]]; then
    curl -fL --retry 3 -o "$PIPER_JSON.part" "$PIPER_BASE_URL/${PIPER_VOICE}.onnx.json"
    mv "$PIPER_JSON.part" "$PIPER_JSON"
  fi
}

start_recording() {
  notify "🎙 Recording… press the hotkey again to stop." 0
  parec --device="@DEFAULT_SOURCE@" --format=s16le --rate=16000 --channels=1 --file-format=wav > "$AUDIO_FILE" &
  echo $! > "$PID_FILE"
  log "started recording pid=$!"
}

stop_recording() {
  local pid
  pid=$(cat "$PID_FILE")
  rm -f "$PID_FILE"
  if kill -0 "$pid" 2>/dev/null; then
    kill "$pid"
    wait "$pid" 2>/dev/null || true
  fi
  log "stopped recording"
}

transcribe() {
  whisper-cli \
    --model "$WHISPER_MODEL" \
    --language en \
    --no-prints \
    --output-txt \
    --file "$AUDIO_FILE" >/dev/null
  tr -d '\r' < "${AUDIO_FILE}.txt" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

query_claude() {
  local user_text="$1"
  local args=(
    --print
    --model "$CLAUDE_MODEL"
    --output-format text
    --permission-mode bypassPermissions
    --append-system-prompt "$VOICE_SYSTEM_PROMPT"
  )
  cd "$WORKSPACE_DIR"
  if [[ -d "$HOME/.claude/projects" ]] && find "$HOME/.claude/projects" -maxdepth 1 -type d -name "*voice-assistant*workspace*" 2>/dev/null | grep -q .; then
    claude "${args[@]}" --continue "$user_text" 2>/dev/null \
      || claude "${args[@]}" "$user_text"
  else
    claude "${args[@]}" "$user_text"
  fi
}

strip_markdown() {
  # shellcheck disable=SC2016
  sed -E '
    s/```[^`]*```//g;
    s/`([^`]*)`/\1/g;
    s/\*\*([^*]+)\*\*/\1/g;
    s/\*([^*]+)\*/\1/g;
    s/__([^_]+)__/\1/g;
    s/^#+[[:space:]]*//;
    s/\[([^]]+)\]\([^)]+\)/\1/g;
    s/^[[:space:]]*[-*+][[:space:]]+/. /;
  '
}

speak() {
  local text="$1"
  printf '%s\n' "$text" | strip_markdown | piper \
    --model "$PIPER_ONNX" \
    --config "$PIPER_JSON" \
    --output_raw 2>/dev/null \
    | pw-cat --rate 22050 --channels 1 --format s16 --playback -
}

main() {
  if [[ -f "$PID_FILE" ]]; then
    stop_recording
    notify "🧠 Processing…" 2000
    ensure_models
    local transcript
    transcript=$(transcribe)
    if [[ -z "$transcript" ]]; then
      notify "✗ No speech detected." 3000
      exit 0
    fi
    log "user: $transcript"
    notify "🗣 $transcript" 4000
    local reply
    if ! reply=$(query_claude "$transcript"); then
      notify "✗ Claude Code failed (run 'claude auth' if first time)." 6000
      exit 1
    fi
    log "assistant: $reply"
    notify "💬 $reply" 6000
    speak "$reply"
  else
    ensure_models
    start_recording
  fi
}

main "$@"
