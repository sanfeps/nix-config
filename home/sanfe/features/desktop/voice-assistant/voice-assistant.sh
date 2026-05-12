#!/usr/bin/env bash
# Voice assistant: hotkey toggles between recording mic and sending the
# transcription to Claude, then speaks the reply.
#
# API key resolution order:
#   1. $ANTHROPIC_API_KEY environment variable
#   2. $XDG_CONFIG_HOME/voice-assistant/api-key (one line, no trailing newline)
set -euo pipefail

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/voice-assistant"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/voice-assistant"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/voice-assistant"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/voice-assistant"
mkdir -p "$STATE_DIR" "$CACHE_DIR" "$CONFIG_DIR" "$DATA_DIR"

PID_FILE="$STATE_DIR/recording.pid"
AUDIO_FILE="$STATE_DIR/recording.wav"
HISTORY_FILE="$DATA_DIR/history.json"
LOG_FILE="$STATE_DIR/voice-assistant.log"

WHISPER_MODEL_NAME="ggml-medium.en.bin"
WHISPER_MODEL="$CACHE_DIR/$WHISPER_MODEL_NAME"
WHISPER_MODEL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$WHISPER_MODEL_NAME"

PIPER_VOICE="en_US-amy-medium"
PIPER_ONNX="$CACHE_DIR/${PIPER_VOICE}.onnx"
PIPER_JSON="$CACHE_DIR/${PIPER_VOICE}.onnx.json"
PIPER_BASE_URL="https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/amy/medium"

CLAUDE_MODEL="claude-haiku-4-5-20251001"
SYSTEM_PROMPT="You are a concise voice assistant. Answer in one or two short spoken sentences unless the user asks for more. Do not use markdown; reply in plain prose."

log() { printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*" >> "$LOG_FILE"; }
notify() { notify-send -a "voice-assistant" -t "${2:-3000}" "Voice assistant" "$1" || true; }

resolve_api_key() {
  if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
    printf '%s' "$ANTHROPIC_API_KEY"
    return
  fi
  if [[ -r "$CONFIG_DIR/api-key" ]]; then
    tr -d '\n' < "$CONFIG_DIR/api-key"
    return
  fi
  return 1
}

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
  cat "${AUDIO_FILE}.txt" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

ensure_history() {
  if [[ ! -s "$HISTORY_FILE" ]]; then
    echo '[]' > "$HISTORY_FILE"
  fi
}

query_claude() {
  local user_text="$1" api_key="$2"
  ensure_history
  local messages
  messages=$(jq -c --arg t "$user_text" '. + [{role:"user", content:$t}]' "$HISTORY_FILE")
  local payload
  payload=$(jq -nc \
    --arg model "$CLAUDE_MODEL" \
    --arg system "$SYSTEM_PROMPT" \
    --argjson messages "$messages" \
    '{model:$model, max_tokens:512, system:$system, messages:$messages}')
  local response
  response=$(curl -fsS https://api.anthropic.com/v1/messages \
    -H "x-api-key: $api_key" \
    -H "anthropic-version: 2023-06-01" \
    -H "content-type: application/json" \
    --data "$payload")
  local reply
  reply=$(jq -r '.content[0].text // ""' <<<"$response")
  jq -c --arg t "$reply" '. + [{role:"assistant", content:$t}]' <<<"$messages" > "$HISTORY_FILE"
  printf '%s' "$reply"
}

speak() {
  local text="$1"
  printf '%s\n' "$text" | piper \
    --model "$PIPER_ONNX" \
    --config "$PIPER_JSON" \
    --output_raw 2>/dev/null \
    | pw-cat --rate 22050 --channels 1 --format s16 --playback -
}

main() {
  if [[ -f "$PID_FILE" ]]; then
    stop_recording
    notify "🧠 Processing…" 2000
    local api_key
    if ! api_key=$(resolve_api_key); then
      notify "✗ No ANTHROPIC_API_KEY set and no $CONFIG_DIR/api-key file." 6000
      exit 1
    fi
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
    reply=$(query_claude "$transcript" "$api_key")
    log "assistant: $reply"
    notify "💬 $reply" 6000
    speak "$reply"
  else
    ensure_models
    start_recording
  fi
}

main "$@"
