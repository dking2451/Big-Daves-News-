#!/usr/bin/env bash
set -euo pipefail

WORKDIR="${1:-$(pwd)}"
PYTHON_BIN="$WORKDIR/.venv/bin/python"
PLIST_PATH="$HOME/Library/LaunchAgents/com.factnews.daily-email.plist"
LOG_DIR="$WORKDIR/logs"

mkdir -p "$LOG_DIR"
mkdir -p "$HOME/Library/LaunchAgents"

cat > "$PLIST_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.factnews.daily-email</string>
  <key>ProgramArguments</key>
  <array>
    <string>$PYTHON_BIN</string>
    <string>-m</string>
    <string>app.daily_scheduler</string>
  </array>
  <key>WorkingDirectory</key>
  <string>$WORKDIR</string>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>$LOG_DIR/scheduler.out.log</string>
  <key>StandardErrorPath</key>
  <string>$LOG_DIR/scheduler.err.log</string>
</dict>
</plist>
PLIST

launchctl unload "$PLIST_PATH" >/dev/null 2>&1 || true
launchctl load "$PLIST_PATH"
launchctl start com.factnews.daily-email

echo "Installed and started launch agent: $PLIST_PATH"
echo "Logs: $LOG_DIR/scheduler.out.log and $LOG_DIR/scheduler.err.log"
