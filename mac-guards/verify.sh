#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
OUT="$HERE/../out/mac-guards"
mkdir -p "$OUT"
umask 077
/usr/bin/python3 "$HERE/guard.py" watch > "$OUT/post-install-watch.json"
sudo /usr/bin/python3 "$HERE/verify-root.py" > "$OUT/pf-verification.json"
/bin/launchctl print "gui/$(id -u)/com.local.ai-watch" > "$OUT/watcher-launchctl.txt"
/bin/launchctl print system/com.local.artme-ai-guard > "$OUT/firewall-launchctl.txt"
echo 'Live checks passed. Reports: out/mac-guards/post-install-watch.json and pf-verification.json'
