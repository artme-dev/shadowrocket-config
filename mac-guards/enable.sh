#!/bin/sh
# Run as the normal logged-in user; sudo will ask in the user's Terminal.
set -eu
[ "$(id -u)" != 0 ] || { echo 'Run this script WITHOUT sudo; it requests administrator rights itself.'; exit 1; }
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
/usr/bin/python3 "$HERE/prepare.py"
# Healthy real-service probes are a prerequisite for arming process termination.
/usr/bin/python3 "$HERE/guard.py" watch
sudo "$HERE/install-root.sh"
mkdir -p "$HOME/Library/LaunchAgents"
/usr/bin/install -m 644 "$HERE/com.local.ai-watch.plist" "$HOME/Library/LaunchAgents/com.local.ai-watch.plist"
/bin/launchctl bootout "gui/$(id -u)/com.local.ai-watch" 2>/dev/null || true
/bin/launchctl enable "gui/$(id -u)/com.local.ai-watch"
/bin/launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.local.ai-watch.plist"
echo 'Watcher armed: two matching wrong-IP responses close Codex/ChatGPT; timeouts do not.'
"$HERE/verify.sh"
echo 'Installation and live verification complete; VPN was not switched.'
