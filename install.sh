#!/bin/bash
# Install the memory-watch LaunchAgent for the current user.
# No sudo. Re-running replaces the previous install cleanly.
set -euo pipefail

LABEL="local.memory-watch"
INTERVAL="${MEM_CHECK_INTERVAL:-900}"
THRESHOLD="${MEM_THRESHOLD_PCT:-20}"
HERE="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$HOME/Library/Application Support/MemoryWatch"
SCRIPT="$APP_DIR/memory-watch.sh"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

plist_content() {
cat <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$SCRIPT</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>MEM_THRESHOLD_PCT</key>
        <string>$THRESHOLD</string>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>StartInterval</key>
    <integer>$INTERVAL</integer>
    <key>LimitLoadToSessionType</key>
    <string>Aqua</string>
    <key>StandardOutPath</key>
    <string>$HOME/Library/Logs/memory-watch.out.log</string>
    <key>StandardErrorPath</key>
    <string>$HOME/Library/Logs/memory-watch.err.log</string>
</dict>
</plist>
PLIST
}

if [ "${DRY_RUN:-0}" = "1" ]; then
    plist_content
    exit 0
fi

mkdir -p "$APP_DIR" "$HOME/Library/LaunchAgents"
install -m 755 "$HERE/memory-watch.sh" "$SCRIPT"
plist_content > "$PLIST"

launchctl bootout "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"

printf 'Installed %s\n' "$LABEL"
printf 'Check interval: %s seconds\n' "$INTERVAL"
printf 'Free-memory threshold: %s%%\n' "$THRESHOLD"
printf 'Log: %s\n' "$HOME/Library/Logs/memory-watch.log"
