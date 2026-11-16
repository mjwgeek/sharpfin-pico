#!/bin/sh
# Revo Pico/Sharpfin: download a prebuilt M3U from HTTP and refresh uShare
# only when the feed changes. For BusyBox ash on the 2007 Pico.
# Save on the persistent mtd5 partition. Requires pico_station_refresh_v03.sh.
set -u

DATA=/mnt/ramfs/var/data
BASE="$DATA/PicoStationDirectory"
IMPORTER="$BASE/pico_station_refresh_v03.sh"
URL=http://reciva.wg5eek.com/stations.m3u
STATE="$BASE/last_imported_feed.m3u"
LOCK="$BASE/.auto_update_lock"
TMP="$BASE/.new_feed.$$"

say() { echo "pico-auto: $*"; }
fail() { say "ERROR: $*" >&2; exit 1; }
cleanup() {
  rm -f "$TMP"
  [ "${LOCKED:-no}" = yes ] && rmdir "$LOCK" 2>/dev/null || true
}

case "${1:-update}" in
  update|check) MODE="${1:-update}" ;;
  *) echo "Usage: sh $0 [check|update]"; exit 2 ;;
esac

# Refuse writes if mtd5 is not mounted. Avoid filling RAM or mtd4.
grep ' /mnt/ramfs/var/data ' /proc/mounts >/dev/null 2>&1 || fail 'mtd5 not mounted'
[ -d "$BASE" ] || fail "Directory missing: $BASE (run importer first)"
[ -f "$IMPORTER" ] || fail "Importer missing: $IMPORTER"
[ -f /opt/etc/ushare.conf ] || fail 'uShare config missing'

if [ "$MODE" = check ]; then
  say "URL: $URL"
  say "Importer: $IMPORTER"
  say "Saved feed: $STATE"
  [ ! -f "$STATE" ] || wc -c "$STATE"
  echo 'Pico clock:'; date
  echo 'Scheduler/processes:'
  ps | grep '[c]rond\|[u]share' || true
  exit 0
fi

LOCKED=no
mkdir "$LOCK" 2>/dev/null || fail 'Already running (or stale lock)'
LOCKED=yes
trap 'cleanup' 0 1 2 3 15

# Fetch only cached static file: no modern API calls from Pico.
# Pico uses HTTP intentionally, not HTTPS.
say "Fetching $URL"
curl -f -s -S --connect-timeout 8 --max-time 30 -o "$TMP" "$URL" || fail 'Download failed; existing library untouched'
[ -s "$TMP" ] || fail 'Empty feed; existing library untouched'
head -n 1 "$TMP" | grep '^#EXTM3U' >/dev/null 2>&1 || fail 'Invalid feed header'
grep '^http' "$TMP" >/dev/null 2>&1 || fail 'Feed contains no stream URLs'

if [ -f "$STATE" ] && cmp "$TMP" "$STATE" >/dev/null 2>&1; then
  say 'No changes: leaving uShare running'
  exit 0
fi

say 'New feed detected: importing genres'
sh "$IMPORTER" import "$TMP" || fail 'Import failed; existing library preserved'

# Rebuild the working UPnP index; never rerun run_ushare.sh or remote-m3u.
say 'Restarting uShare (no Pico reboot)'
killall ushare 2>/dev/null || true
sleep 2
/opt/bin/ushare -f /opt/etc/ushare.conf >/tmp/pico-ushare-start.log 2>&1 &
sleep 3
ps | grep '[u]share' >/dev/null 2>&1 || fail 'uShare did not appear to restart; feed state not committed'

# Record success. If this fails, next run will attempt import again.
cp "$TMP" "$STATE" || fail 'Could not save last successful feed'
say 'Updated and refreshed successfully'