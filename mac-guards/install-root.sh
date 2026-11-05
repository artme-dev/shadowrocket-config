#!/bin/sh
# Privileged half. Use enable.sh from the normal user session.
set -eu
[ "$(id -u)" = 0 ] || { echo 'Run through mac-guards/enable.sh'; exit 1; }
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SOURCE="$HERE/../out/mac-guards"
ETC=/usr/local/etc/artme-ai-guard
ANCHOR=com.apple/249.ArtmeAIGuard
for file in policy.json dns-cache.json; do test -s "$SOURCE/$file"; done
/usr/bin/plutil -lint "$HERE/com.local.artme-ai-guard.plist"
/usr/bin/python3 -m py_compile "$HERE/firewall.py"
/sbin/pfctl -n -a "$ANCHOR" -f "$SOURCE/pf.rules"
# The existing system anchor must be present; never reload the main firewall.
/sbin/pfctl -s rules | /usr/bin/grep -q 'anchor "com.apple/\*"' || {
  echo 'Main com.apple/* anchor missing. No firewall changes made.'; exit 1;
}
BACKUP="/var/root/artme-ai-guard-backup-$(date '+%Y%m%d-%H%M%S')"
mkdir -m 700 "$BACKUP"
/sbin/pfctl -a "$ANCHOR" -s rules > "$BACKUP/previous.rules"
for label in openai-killswitch anthropic-killswitch; do
  /bin/launchctl print "system/com.local.$label" > "$BACKUP/$label.launchctl" 2>/dev/null || true
  /sbin/pfctl -a "com.apple/$(test "$label" = openai-killswitch && echo 251.OpenAIKillswitch || echo 250.AnthropicKillswitch)" -s rules > "$BACKUP/$label.rules"
done
[ ! -d "$ETC" ] || cp -pR "$ETC" "$BACKUP/etc"
[ ! -f /usr/local/libexec/artme-ai-guard.py ] || cp -p /usr/local/libexec/artme-ai-guard.py "$BACKUP/"
/usr/bin/install -d -o root -g wheel -m 700 "$ETC"
/usr/bin/install -d -o root -g wheel -m 755 /usr/local/libexec
/usr/bin/install -o root -g wheel -m 600 "$SOURCE/policy.json" "$SOURCE/dns-cache.json" "$ETC/"
/usr/bin/install -o root -g wheel -m 755 "$HERE/firewall.py" /usr/local/libexec/artme-ai-guard.py
# Validate and apply before retiring either legacy guard. On error no legacy job is removed.
if ! /usr/bin/python3 /usr/local/libexec/artme-ai-guard.py apply; then
  if [ -d "$BACKUP/etc" ]; then
    cp -pR "$BACKUP/etc/." "$ETC/"
    cp -p "$BACKUP/artme-ai-guard.py" /usr/local/libexec/artme-ai-guard.py
  fi
  echo "Apply failed. Legacy guards retained. Backup: $BACKUP"; exit 1
fi
/usr/bin/install -o root -g wheel -m 644 "$HERE/com.local.artme-ai-guard.plist" /Library/LaunchDaemons/
/bin/launchctl bootout system/com.local.artme-ai-guard 2>/dev/null || true
/bin/launchctl enable system/com.local.artme-ai-guard
/bin/launchctl bootstrap system /Library/LaunchDaemons/com.local.artme-ai-guard.plist
# Prevent reactivation of old jobs after reboot; keep their installed files for rollback.
for label in openai-killswitch anthropic-killswitch; do
  /bin/launchctl bootout "system/com.local.$label" 2>/dev/null || true
  /bin/launchctl disable "system/com.local.$label"
done
/sbin/pfctl -a com.apple/250.AnthropicKillswitch -F rules
/sbin/pfctl -a com.apple/251.OpenAIKillswitch -F rules
# Narrow flushes only. No -F states, -F all on root, pfctl -d or VPN action.
echo "Root firewall installed. Backup: $BACKUP"
/sbin/pfctl -s info | head -3
/sbin/pfctl -a "$ANCHOR" -s Tables
