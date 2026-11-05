#!/bin/sh
# Manual emergency rollback of ONLY the new guards. Does not enable obsolete jobs.
set -eu
if [ "$(id -u)" != 0 ]; then
  /bin/launchctl bootout "gui/$(id -u)/com.local.ai-watch" 2>/dev/null || true
  /bin/launchctl disable "gui/$(id -u)/com.local.ai-watch"
  exec sudo "$0"
fi
/bin/launchctl bootout system/com.local.artme-ai-guard 2>/dev/null || true
/bin/launchctl disable system/com.local.artme-ai-guard
/sbin/pfctl -a com.apple/249.ArtmeAIGuard -F rules
if [ -f /var/run/artme-ai-guard.token ]; then
  /sbin/pfctl -X "$(cat /var/run/artme-ai-guard.token)"
  rm /var/run/artme-ai-guard.token
fi
echo 'New guards disabled; VPN and unrelated firewall anchors unchanged.'
