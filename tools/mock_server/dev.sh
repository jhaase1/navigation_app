#!/bin/bash
# Start the mock rig and the app together, wired to point at each other.
#
#   ./tools/mock_server/dev.sh                   switcher + 3 cameras, flutter run on this OS's desktop device
#   ./tools/mock_server/dev.sh --no-cameras      switcher only
#   ./tools/mock_server/dev.sh --device chrome   any other flutter device
#   ./tools/mock_server/dev.sh --no-inspector    skip opening the inspector in Chrome
#
# The inspector (http://127.0.0.1:8080) opens in Chrome once the rig is up,
# so you can watch what each command actually did alongside the app.
#
# Cameras answer on port 80, normally privileged. Run
# tools/mock_server/setup-no-sudo.sh once (needs sudo that one time) and
# every run after that -- this one included -- needs no root. Skip that and
# --cameras still works, run.py just asks for sudo the moment a bind
# actually needs it, instead of demanding it up front.
#
# The app is launched with --dart-define=MOCK_RIG=true, which points its
# default Roland/camera addresses at this rig instead of the real church
# network (see DeviceConfigStore.mockRig) -- no manual Settings edits needed.
#
# Ctrl-C, or quitting the app, stops both: the rig has its own SIGINT handler
# that tears down any loopback aliases it created, so cleanup here only has to
# make sure that signal actually reaches it.
#
# Web is a dead end for the switcher: RolandService uses dart:io sockets,
# which don't exist in a browser (see tools/mock_server/README.md). Web is
# fine for camera-only testing, or just eyeballing the UI.

set -euo pipefail
set -m  # background jobs get their own process group, so cleanup can signal
        # the whole group instead of just the direct child.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_ROOT"

case "$(uname -s)" in
  Darwin) DEVICE="macos" ;;
  Linux) DEVICE="linux" ;;
  MINGW*|MSYS*|CYGWIN*) DEVICE="windows" ;;
  *) DEVICE="" ;;
esac
CAMERAS=1
ROLAND_PORT=8023
INSPECTOR_PORT=8080
OPEN_INSPECTOR=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cameras) CAMERAS=1; shift ;;
    --no-cameras) CAMERAS=0; shift ;;
    --device) DEVICE="${2:?usage: --device <flutter-device>}"; shift 2 ;;
    --no-inspector) OPEN_INSPECTOR=0; shift ;;
    -h|--help) sed -n '2,28p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$DEVICE" ]]; then
  echo "Couldn't map $(uname -s) to a flutter desktop device -- pass one explicitly with --device." >&2
  exit 1
fi

open_inspector_in_chrome() {
  local url="http://127.0.0.1:$INSPECTOR_PORT"
  case "$(uname -s)" in
    Darwin)
      open -a "Google Chrome" "$url" 2>/dev/null || open "$url"
      ;;
    Linux)
      local chrome_bin
      chrome_bin="$(command -v google-chrome || command -v google-chrome-stable \
        || command -v chromium-browser || command -v chromium || true)"
      if [[ -n "$chrome_bin" ]]; then
        nohup "$chrome_bin" "$url" >/dev/null 2>&1 &
        disown
      elif command -v xdg-open >/dev/null; then
        echo "Chrome not found; opening the inspector with the default browser instead." >&2
        nohup xdg-open "$url" >/dev/null 2>&1 &
        disown
      else
        echo "No way to open a browser found -- inspector is at $url" >&2
      fi
      ;;
    MINGW*|MSYS*|CYGWIN*)
      cmd.exe /c start chrome "$url" 2>/dev/null || cmd.exe /c start "$url"
      ;;
    *)
      echo "Don't know how to open a browser on $(uname -s) -- inspector is at $url" >&2
      ;;
  esac
}

rig_cmd=(python3 tools/mock_server/run.py)
[[ "$CAMERAS" == 1 ]] || rig_cmd+=(--no-cameras)

echo "Starting mock rig: ${rig_cmd[*]}"
"${rig_cmd[@]}" &
RIG_PID=$!

cleanup() {
  if kill -0 "$RIG_PID" 2>/dev/null; then
    echo
    echo "Stopping mock rig (pid $RIG_PID)..."
    kill -INT -- "-$RIG_PID" 2>/dev/null || true
    wait "$RIG_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

echo "Waiting for the switcher on 127.0.0.1:$ROLAND_PORT..."
until (exec 3<>"/dev/tcp/127.0.0.1/$ROLAND_PORT") 2>/dev/null; do
  if ! kill -0 "$RIG_PID" 2>/dev/null; then
    echo "Mock rig exited before it came up -- see output above." >&2
    exit 1
  fi
  sleep 0.1
done
exec 3>&- 3<&- 2>/dev/null || true

if [[ "$OPEN_INSPECTOR" == 1 ]]; then
  echo "Opening the inspector in Chrome (http://127.0.0.1:$INSPECTOR_PORT)..."
  open_inspector_in_chrome
fi

echo "Rig is up. Launching the app (flutter run -d $DEVICE)..."
echo "  Keep the app in Live mode, not Demo -- Demo never touches the network."
echo

flutter run -d "$DEVICE" --dart-define=MOCK_RIG=true
