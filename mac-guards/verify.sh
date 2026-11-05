#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
OUT="$HERE/../out/mac-guards"
mkdir -p "$OUT"
umask 077
# A concurrent LaunchAgent cycle must not masquerade as an empty successful probe.
attempt=0
while :; do
  if /usr/bin/python3 "$HERE/guard.py" watch > "$OUT/post-install-watch.tmp"; then
    mv "$OUT/post-install-watch.tmp" "$OUT/post-install-watch.json"
    break
  else
    code=$?
    attempt=$((attempt + 1))
    if [ "$code" != 75 ] || [ "$attempt" -ge 10 ]; then
      rm -f "$OUT/post-install-watch.tmp"
      echo 'Route observation failed or stayed busy; verification not complete.' >&2
      exit "$code"
    fi
    sleep 2
  fi
done
sudo /usr/bin/python3 "$HERE/verify-root.py" > "$OUT/pf-verification.json"
/bin/launchctl print "gui/$(id -u)/com.local.ai-watch" > "$OUT/watcher-launchctl.txt"
/bin/launchctl print system/com.local.artme-ai-guard > "$OUT/firewall-launchctl.txt"
echo 'Live checks passed. Reports: out/mac-guards/post-install-watch.json and pf-verification.json'
