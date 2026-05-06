#!/usr/bin/env bash
set -euo pipefail

target=""
ssh_port=22
auth_key=""

usage() {
  cat <<'EOF'
Usage: install-tailscale-auth-key.sh --target user@host [--port 22] [--auth-key KEY]

Installs a Headscale/Tailscale auth key on a host configured with
hosts/optional/tailscale.nix, then restarts the auto-connect service.

If --auth-key is omitted, the script prompts for it without echo.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)
      shift
      target="${1:-}"
      ;;
    --port)
      shift
      ssh_port="${1:-}"
      ;;
    --auth-key)
      shift
      auth_key="${1:-}"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

if [[ -z "$target" ]]; then
  echo "--target is required" >&2
  usage >&2
  exit 1
fi

if [[ -z "$auth_key" ]]; then
  read -r -s -p "Headscale auth key: " auth_key
  echo
fi

if [[ -z "$auth_key" ]]; then
  echo "Auth key cannot be empty" >&2
  exit 1
fi

tmpfile="$(mktemp)"
trap 'rm -f "$tmpfile"' EXIT
printf '%s\n' "$auth_key" > "$tmpfile"

scp -P "$ssh_port" "$tmpfile" "$target:/tmp/tailscale-auth-key"
ssh -p "$ssh_port" "$target" '
  install -d -m 700 /persist/secrets
  install -m 600 /tmp/tailscale-auth-key /persist/secrets/tailscale-auth-key
  rm -f /tmp/tailscale-auth-key
  systemctl restart tailscale-autoconnect-valgrindr.service
  systemctl --no-pager --full status tailscale-autoconnect-valgrindr.service
'
