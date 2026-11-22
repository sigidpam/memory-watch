#!/bin/bash
# Remove the memory-watch LaunchAgent and installed script.
set -u

LABEL="local.memory-watch"
APP_DIR="$HOME/Library/Application Support/MemoryWatch"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

launchctl bootout "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || true
rm -f "$PLIST" "$APP_DIR/memory-watch.sh"
rmdir "$APP_DIR" 2>/dev/null || true

printf 'Removed %s\n' "$LABEL"
