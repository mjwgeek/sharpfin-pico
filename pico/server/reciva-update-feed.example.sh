#!/bin/sh
# Reference only: the server's actual installed script was not captured.
# Requires WEBROOT exported as a nonempty path to the existing document root.
set -eu
[ -n "$WEBROOT" ] || { echo 'Set WEBROOT to the HTTP document root' >&2; exit 1; }
SOURCE=http://reciva.wg5eek.com/php_feed.php
DEST="$WEBROOT/stations.m3u"
[ -d "$WEBROOT" ] || exit 1
TMP="$(mktemp "$WEBROOT/.stations.m3u.XXXXXX")"
trap 'rm -f "$TMP"' EXIT HUP INT TERM
curl -fSs --connect-timeout 10 --max-time 180 "$SOURCE" -o "$TMP"
head -n 1 "$TMP" | grep -q '^#EXTM3U' || exit 1
grep -q '^#EXTINF:' "$TMP" || exit 1
grep -q '^http://' "$TMP" || exit 1
if grep -q '^https://' "$TMP"; then echo 'HTTPS stream URLs remain' >&2; exit 1; fi
BYTES="$(wc -c < "$TMP")"
[ "$BYTES" -lt 300000 ] || { echo "Feed too large: $BYTES bytes" >&2; exit 1; }
chmod 644 "$TMP"
mv -f "$TMP" "$DEST"
echo "$(date -Is) Updated $BYTES bytes"
