#!/usr/bin/env bash
set -euo pipefail

WORKDIR="${1:-$(pwd)}"
SCRIPT_PATH="$WORKDIR/scripts/start_public_tunnel.sh"
PLIST_PATH="$HOME/Library/LaunchAgents/com.factnews.public-tunnel.plist"
LOG_DIR="$WORKDIR/logs"

mkdir -p "$LOG_DIR"
mkdir -p "$HOME/Library/LaunchAgents"

cat > "$PLIST_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.factnews.public-tunnel</string>
  <key>ProgramArguments</key>
  <array>
    <string>$SCRIPT_PATH</string>
  </array>
  <key>WorkingDirectory</key>
  <string>$WORKDIR</string>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>$LOG_DIR/tunnel.out.log</string>
  <key>StandardErrorPath</key>
  <string>$LOG_DIR/tunnel.err.log</string>
</dict>
</plist>
PLIST

launchctl unload "$PLIST_PATH" >/dev/null 2>&1 || true
launchctl load "$PLIST_PATH"
launchctl start com.factnews.public-tunnel

echo "Installed and started tunnel launch agent: $PLIST_PATH"
echo "Tunnel logs: $LOG_DIR/tunnel.out.log and $LOG_DIR/tunnel.err.log"
