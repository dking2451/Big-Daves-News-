#!/usr/bin/env bash
set -euo pipefail

WORKDIR="$(cd "$(dirname "$0")/.." && pwd)"
LOG_FILE="$WORKDIR/logs/tunnel.log"
URL_FILE="$WORKDIR/data/public_report_url.txt"
CLOUDFLARED_BIN="$WORKDIR/bin/cloudflared"

mkdir -p "$WORKDIR/logs" "$WORKDIR/data"
touch "$LOG_FILE"

if [ ! -x "$CLOUDFLARED_BIN" ]; then
  echo "cloudflared binary not found at $CLOUDFLARED_BIN" | tee -a "$LOG_FILE"
  exit 1
fi

echo "$(date) starting cloudflared tunnel..." >> "$LOG_FILE"
"$CLOUDFLARED_BIN" tunnel --no-autoupdate --url http://localhost:8001 2>&1 | while IFS= read -r line; do
  echo "$line" >> "$LOG_FILE"
  url="$(printf "%s\n" "$line" | sed -nE 's#.*(https://[a-zA-Z0-9-]+\.trycloudflare\.com).*#\1#p')"
  if [ -n "$url" ]; then
    echo "$url/" > "$URL_FILE"
    echo "$(date) public URL updated: $url/" >> "$LOG_FILE"
  fi
done
