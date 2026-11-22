# memory-watch

macOS memory watchdog. When free memory drops below a threshold, it shows the biggest user apps and asks which one to quit. Every quit needs a second confirmation, and quitting uses the app's normal Quit command so unsaved documents get that app's own save prompt.

## Safety model

- Nothing quits without two explicit clicks: choose an app, then confirm **Quit Now**.
- **Skip** / **Cancel** leaves every process running.
- Never uses `kill -9`, never force-kills, never runs with `sudo`.
- Only apps under `/Applications` and `~/Applications` are listed. Helpers inside a bundle count toward the parent app, so Brave Helper processes are attributed to Brave Browser.
- Quit uses an AppleEvent. The app decides whether to save, prompt, or refuse.
- If macOS blocks Automation, the script logs the failure and shows an alert instead of killing anything.

## Requirements

- macOS 13 or newer.
- `/usr/bin/python3` (installed with Xcode Command Line Tools).

## Install

```sh
git clone https://github.com/sigidpam/memory-watch.git
cd memory-watch
./install.sh
```

Defaults: check every 900 seconds (15 minutes), trigger below 20% free memory. Override at install time:

```sh
MEM_CHECK_INTERVAL=600 MEM_THRESHOLD_PCT=15 ./install.sh
```

`MEM_CHECK_INTERVAL` is written into the LaunchAgent. `MEM_THRESHOLD_PCT` is passed through the LaunchAgent environment. Re-running `install.sh` replaces the previous agent.

The threshold comes from `memory_pressure`'s "System-wide memory free percentage".

## Test without quitting anything

```sh
MEM_THRESHOLD_PCT=100 MEM_WATCH_DRY_RUN=1 bash "$HOME/Library/Application Support/MemoryWatch/memory-watch.sh"
```

This forces the dialog at any memory level. Confirming **Quit Now** only logs the intended action when `MEM_WATCH_DRY_RUN=1`.

List what would be offered, without a dialog:

```sh
MEM_THRESHOLD_PCT=100 MEM_WATCH_LIST_ONLY=1 bash "$HOME/Library/Application Support/MemoryWatch/memory-watch.sh"
```

## Logs

- `~/Library/Logs/memory-watch.log` — checks, decisions, quit requests.
- `~/Library/Logs/memory-watch.err.log` — LaunchAgent and AppleScript errors.

## Automation permission

The first time the watchdog asks a given app to quit, macOS may ask for Automation permission. Approve it if you want that app to receive the Quit command. Denying is safe: nothing is killed, and the watchdog shows an alert.

## Check status

```sh
launchctl print "gui/$(id -u)/local.memory-watch" | grep -E 'state|last exit|run interval'
```

## Uninstall

```sh
./uninstall.sh
```

## Files

- `memory-watch.sh` — the check, app ranking, dialogs, and quit logic.
- `install.sh` — writes the LaunchAgent into `~/Library/LaunchAgents` and loads it.
- `uninstall.sh` — unloads and removes the agent and installed script.
