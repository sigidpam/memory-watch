#!/bin/bash
# Memory watchdog for macOS.
# Every run: if free memory is below the threshold, list the biggest user apps
# and let the user pick one. A second dialog must confirm the quit. Quit uses
# the app's normal Quit command, so unsaved work triggers that app's own save
# prompt. This script never force-kills and never quits anything without an
# explicit click. One instance at a time.

set -u
export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin

THRESHOLD_PCT="${MEM_THRESHOLD_PCT:-20}"
DRY_RUN="${MEM_WATCH_DRY_RUN:-0}"
LIST_ONLY="${MEM_WATCH_LIST_ONLY:-0}"
LOG_DIR="$HOME/Library/Logs"
LOG="$LOG_DIR/memory-watch.log"
LOCK="/tmp/memory-watch.$(id -u).lock"

mkdir -p "$LOG_DIR"

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG"; }

# Rotate a runaway log
if [ -f "$LOG" ] && [ "$(stat -f%z "$LOG" 2>/dev/null || echo 0)" -gt 524288 ]; then
    tail -n 400 "$LOG" > "$LOG.tmp" 2>/dev/null && mv "$LOG.tmp" "$LOG"
fi

# One instance. Drop a stale lock older than 10 minutes.
if ! mkdir "$LOCK" 2>/dev/null; then
    age=$(( $(date +%s) - $(stat -f%m "$LOCK" 2>/dev/null || echo 0) ))
    if [ "$age" -gt 600 ] && rmdir "$LOCK" 2>/dev/null && mkdir "$LOCK" 2>/dev/null; then
        :
    else
        exit 0
    fi
fi
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

if [ ! -x /usr/bin/python3 ]; then
    log "python3 not found at /usr/bin/python3; skipping run"
    exit 0
fi

free_pct=$(memory_pressure 2>/dev/null | awk -F': ' '/System-wide memory free percentage/ {gsub(/%/,"",$2); print $2; exit}')
if [ -z "${free_pct:-}" ]; then
    log "free memory percentage unavailable; skipping run"
    exit 0
fi

swap=$(sysctl -n vm.swapusage 2>/dev/null)
pressure=$(sysctl -n kern.memorystatus_vm_pressure_level 2>/dev/null)
log "check free=${free_pct}% threshold=${THRESHOLD_PCT}% pressure=${pressure:-?} swap=${swap:-?}"

if [ "$free_pct" -ge "$THRESHOLD_PCT" ]; then
    exit 0
fi

# Sum resident memory per app bundle. Helpers that live inside a parent .app
# count toward the parent, so quitting one app targets the whole app.
apps=$(ps -axo rss=,comm= 2>/dev/null | /usr/bin/python3 -I -c '
import os, re, sys
agg = {}
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        rss_s, path = line.split(None, 1)
        rss = int(rss_s)
    except ValueError:
        continue
    m = re.match(r"^(/.*?/([^/]+)\.app)/", path)
    if not m:
        continue
    bundle, name = m.group(1), m.group(2)
    home_apps = os.path.expanduser("~/Applications/")
    if not (bundle.startswith("/Applications/") or bundle.startswith(home_apps)):
        continue
    agg[name] = agg.get(name, 0) + rss
items = sorted(agg.items(), key=lambda kv: kv[1], reverse=True)
for name, kb in items[:8]:
    mb = kb // 1024
    if mb >= 200:
        print(f"{name}\t{mb}")
')
if [ -z "$apps" ]; then
    log "below threshold but no user apps at or above 200 MB"
    exit 0
fi

if [ "$LIST_ONLY" = "1" ]; then
    printf '%s\n' "$apps"
    exit 0
fi

displays=$(printf '%s\n' "$apps" | awk -F'\t' '{printf "%s - %d MB\n", $1, $2}')
names=$(printf '%s\n' "$apps" | cut -f1)

chosen=$(/usr/bin/osascript - "$free_pct" "$displays" "$names" <<'APPLESCRIPT'
on run argv
    set freePct to item 1 of argv
    set displayText to item 2 of argv
    set nameText to item 3 of argv
    set displayItems to paragraphs of displayText
    set appNames to paragraphs of nameText
    set picked to choose from list displayItems with title "Memory Watch" with prompt ("Free memory is " & freePct & "%. Choose an app to quit. Nothing happens unless you confirm the next dialog.") OK button name "Choose" cancel button name "Skip"
    if picked is false then return ""
    set pickedText to item 1 of picked
    set pickedIndex to 0
    repeat with i from 1 to count of displayItems
        if item i of displayItems is pickedText then set pickedIndex to i
    end repeat
    if pickedIndex is 0 then return ""
    set appName to item pickedIndex of appNames
    display dialog ("Quit " & appName & "?" & return & return & "Quit sends the app's normal Quit command. If it has unsaved documents, the app shows its own save prompt. No force-kill is used.") with title "Memory Watch" buttons {"Cancel", "Quit Now"} default button "Cancel" cancel button "Cancel" with icon caution
    return appName
end run
APPLESCRIPT
)
rc=$?
if [ "$rc" -ne 0 ] || [ -z "${chosen:-}" ]; then
    log "user skipped or dialog failed (rc=$rc)"
    exit 0
fi

log "user approved quitting: $chosen"
if [ "$DRY_RUN" = "1" ]; then
    log "dry run: would quit $chosen"
    exit 0
fi

/usr/bin/osascript - "$chosen" >>"$LOG" 2>&1 <<'APPLESCRIPT'
on run argv
    tell application (item 1 of argv) to quit
end run
APPLESCRIPT
qrc=$?
if [ "$qrc" -ne 0 ]; then
    log "quit request failed for $chosen (rc=$qrc; likely missing Automation permission)"
    /usr/bin/osascript -e 'display alert "Memory Watch" message "Could not ask that app to quit. Open System Settings > Privacy & Security > Automation and allow osascript to control it, or quit the app manually." as warning' >/dev/null 2>&1
else
    log "quit requested for $chosen"
fi
