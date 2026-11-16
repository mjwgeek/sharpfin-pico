#!/bin/sh
# Revo Pico / Sharpfin live station updater v0.5
# Uses the 16 MiB mtd5 data partition, NOT the 1 MiB Sharpfin debug partition.
# Purpose: update the existing Media Player > UPnP > Browse radio library.
# The native Reciva Stations menu is NOT modified.
# Compatible with older BusyBox ash (does not use the `command` builtin).
set -eu

DATA=${PICO_STATIONS_DATA:-/mnt/ramfs/var/data}
ROOT=${PICO_STATIONS_ROOT:-/opt/Stations}
BASE="$DATA/PicoStationDirectory"
LIVE="$BASE/Live_Directory"
VISIBLE="$ROOT/Live_Directory"
STARTUP=/opt/bin/run_ushare.sh
CONF=/opt/etc/ushare.conf
WORK=/tmp/pico_station_refresh.$$
LOCK="$BASE/.pico_station_lock"
STAGE="$BASE/.stage.$$"
BACKUP="$BASE/.backup.$$"
OWN_LOCK=no

say() { echo "pico-stations: $*"; }
fail() { echo "pico-stations ERROR: $*" >&2; exit 1; }
# Tool check that works on the original Pico shell (which lacks `command -v`).
have_tool() {
  for p in /bin/$1 /usr/bin/$1 /sbin/$1 /usr/sbin/$1 /opt/bin/$1; do
    [ -x "$p" ] && return 0
  done
  return 1
}
cleanup() {
  if [ "$OWN_LOCK" = yes ]; then
    [ ! -d "$STAGE" ] || rm -rf "$STAGE"
    [ ! -d "$LOCK" ] || rmdir "$LOCK" 2>/dev/null || true
  fi
  [ ! -d "$WORK" ] || rm -rf "$WORK"
}
usage() {
  cat <<'EOF'
Usage:
  sh pico_station_refresh_v05.sh check
  sh pico_station_refresh_v05.sh import /tmp/stations.m3u
  sh pico_station_refresh_v05.sh update 'http://example.com/pico_feed.php?source=radio'
  sh pico_station_refresh_v05.sh refresh [ushare-http-port]

check   : read-only diagnostics (shows BOTH flash partitions)
import  : create genre M3U playlists on the persistent 16 MB data partition
update  : download and import a compatible M3U feed
refresh : ask uShare's local web control interface to rescan; NO process restart

On import, if /opt/Stations/Live_Directory is absent, a tiny symlink is
created there pointing to the playlists on the 16 MB data partition.
Other stations/favorites are never removed. If this uShare build doesn't
follow symlinks, share the persistent directory explicitly in ushare.conf.
EOF
}
check_mount() {
  [ -d "$DATA" ] || fail "Missing data mount: $DATA"
  # Never accidentally write large data into temporary RAM if mtd5 is unmounted.
  if [ "${PICO_STATIONS_TEST_MODE:-no}" != yes ]; then
    grep ' /mnt/ramfs/var/data ' /proc/mounts >/dev/null 2>&1 || fail 'mtd5 data partition is not mounted at /mnt/ramfs/var/data; refusing writes'
  fi
}
check() {
  say 'Environment check (no changes)'
  uname -a 2>/dev/null || true
  for t in awk curl wget wc mv ln mkdir rm grep sed; do
    if have_tool "$t"; then say "$t: available"; else say "$t: missing"; fi
  done
  if [ -d "$DATA" ]; then
    say "Persistent data partition: $DATA"
    df -h "$DATA" 2>/dev/null || true
  else
    say "MISSING persistent data mount: $DATA"
  fi
  if [ -d "$ROOT" ]; then
    say "uShare station root: $ROOT"
    df -h "$ROOT" 2>/dev/null || true
  else
    say "MISSING uShare station root: $ROOT"
  fi
  if [ -L "$VISIBLE" ]; then
    say "Station link exists: $VISIBLE"
    ls -ld "$VISIBLE"
  elif [ -e "$VISIBLE" ]; then
    say "Existing directory (will NOT replace): $VISIBLE"
  else
    say "No generated station link yet: $VISIBLE"
  fi
  if [ -f "$CONF" ]; then
    say "uShare config: $CONF"
    grep '^USHARE_\|^ENABLE_WEB=' "$CONF" 2>/dev/null || true
  else
    say "uShare config not found: $CONF"
  fi
  [ ! -f "$STARTUP" ] || say "Custom startup script found: $STARTUP (not run by updater)"
  ps 2>/dev/null | grep '[u]share' || true
  say 'No services restarted; no files changed.'
}
# Feed format: #EXTM3U, #EXTGRP:Genre, #EXTINF:Station, http://stream...
parse_feed() {
  input=$1
  output=$2
  awk -v out="$output" '
    BEGIN { group="Other"; name=""; total=0; maximum=50 }
    {
      sub(/\r$/, "", $0)
      if (length($0)>1024) { name=""; next }
    }
    /^#EXTGRP:/ {
      group=substr($0, 9)
      gsub(/[^A-Za-z0-9 _-]/, "", group)
      sub(/^ +/, "", group); sub(/ +$/, "", group)
      if (group=="") group="Other"
      group=substr(group,1,40)
      name=""
      next
    }
    /^#EXTINF:/ {
      name=substr($0,9)
      sub(/^-?[0-9]+,/, "", name)
      gsub(/[^ -~]/,"",name)
      sub(/^ +/,"",name); sub(/ +$/, "", name)
      if (length(name)>120) name=substr(name,1,120)
      next
    }
    /^https?:\/\// {
      url=$0
      if (name=="" || length(url)>700 || url ~ /[[:space:]]/ || url ~ /[^ -~]/) { name=""; next }
      if (seen[url]++) { name=""; next }
      if (counts[group]>=maximum) { name=""; next }
      filename=group
      gsub(/ +/,"_",filename)
      target=out "/" filename ".m3u"
      if (!opened[target]) { print "#EXTM3U" > target; opened[target]=1 }
      print "#EXTINF:" name >> target
      print url >> target
      close(target)
      counts[group]++; total++
      name=""
      next
    }
    { if ($0 !~ /^#/) name="" }
    END { print total; if (total<1) exit 3 }
  ' "$input"
}
expose_library() {
  [ -d "$ROOT" ] || { say "No $ROOT: library remains safely stored on mtd5"; return 0; }
  if [ -L "$VISIBLE" ]; then
    if [ -f "$VISIBLE/.pico_generated_v03" ]; then
      say "Existing station link is usable: $VISIBLE"
    else
      say "Existing station symlink points elsewhere; leaving it untouched: $VISIBLE"
    fi
  elif [ -e "$VISIBLE" ]; then
    say "A real directory already exists at $VISIBLE; leaving it untouched"
    say "Add $LIVE as a separate uShare content directory if needed"
  else
    if ln -s "$LIVE" "$VISIBLE"; then
      say "Created small station symlink at $VISIBLE (playlists remain on mtd5)"
    else
      say "Could not link under /opt; playlists remain safe at $LIVE"
    fi
  fi
  say 'Whether this patched uShare scans symlinks still needs verification on the Pico.'
}
import_feed() {
  input=$1
  [ -f "$input" ] || fail "Missing feed: $input"
  have_tool awk || fail 'awk not installed'
  have_tool wc || fail 'wc not installed'
  size=`wc -c < "$input"`
  [ "$size" -gt 10 ] && [ "$size" -lt 300000 ] || fail "Feed should be 11..299999 bytes (got $size)"
  check_mount
  [ -d "$ROOT" ] || fail "Missing current station root: $ROOT"
  mkdir -p "$BASE" || fail "Cannot create $BASE"
  [ ! -e "$STAGE" ] && [ ! -e "$BACKUP" ] || fail 'Stale staging directory; refusing overwrite'
  mkdir "$LOCK" 2>/dev/null || fail "Another refresh is running or stale lock exists: $LOCK"
  OWN_LOCK=yes
  trap 'cleanup' 0 1 2 3 15
  mkdir "$STAGE" || fail 'Could not create staging directory on mtd5'
  count=`parse_feed "$input" "$STAGE"` || fail 'Feed had no valid streams; existing directory preserved'
  # The Pico's old awk can create flat playlist files reliably, but cannot
  # create nested directories itself. Move the COMPLETE playlists into real
  # genre folders from the shell after parsing; no awk system() calls.
  moved=0
  for playlist in "$STAGE"/*.m3u; do
    [ -f "$playlist" ] || continue
    filename=${playlist##*/}
    genre=${filename%.m3u}
    [ -n "$genre" ] || fail 'Invalid empty genre filename'
    mkdir "$STAGE/$genre" || fail "Cannot create genre folder: $genre"
    mv "$playlist" "$STAGE/$genre/Stations.m3u" || fail "Cannot move playlist into genre folder: $genre"
    moved=$((moved + 1))
  done
  [ "$moved" -gt 0 ] || fail 'No genre playlists created; existing library preserved'
  say "Prepared $moved genre folders"
  echo 'Generated by pico_station_refresh_v05.sh (genre folders)' > "$STAGE/.pico_generated_v03"
  if [ -d "$LIVE" ]; then
    [ -f "$LIVE/.pico_generated_v03" ] || fail "Existing directory was not made by this updater: $LIVE"
    mv "$LIVE" "$BACKUP" || fail 'Cannot preserve previous generated station lists'
  elif [ -e "$LIVE" ] || [ -L "$LIVE" ]; then
    fail "Refusing to overwrite existing file or link: $LIVE"
  fi
  if ! mv "$STAGE" "$LIVE"; then
    [ ! -d "$BACKUP" ] || mv "$BACKUP" "$LIVE"
    fail 'Install failed; attempted to restore old list'
  fi
  [ ! -d "$BACKUP" ] || rm -rf "$BACKUP"
  say "Installed $count streams in $moved genre folders on the 16 MB partition: $LIVE"
  expose_library
  say 'Existing station lists are untouched. Use refresh for uShare rescan.'
}
refresh_ushare() {
  port=${1:-}
  [ -n "$port" ] || {
    if [ -f "$CONF" ]; then
      port=`sed -n 's/^USHARE_PORT=//p' "$CONF" | sed -n '1p' | tr -d ' \r\"'`
    fi
  }
  case "$port" in ''|*[!0-9]*) fail 'No valid uShare HTTP port found; use refresh PORT after inspecting /opt/etc/ushare.conf';; esac
  [ "$port" -gt 0 ] && [ "$port" -lt 65536 ] || fail "Invalid uShare port: $port"
  have_tool curl || fail 'curl is required for non-restarting uShare refresh'
  mkdir -p "$WORK"
  say "Requesting uShare content rescan via http://127.0.0.1:$port/web/ushare.cgi?action=refresh"
  if curl -f -s -S --max-time 12 -o "$WORK/response.txt" "http://127.0.0.1:$port/web/ushare.cgi?action=refresh"; then
    say 'uShare web refresh request succeeded; reopen Browse radio to verify.'
  else
    say 'Web refresh is unavailable or disabled; uShare was NOT stopped/restarted.'
    fail 'Show /opt/etc/ushare.conf and /opt/bin/run_ushare.sh to arrange a compatible refresh method'
  fi
  rm -rf "$WORK"
}

case "${1:-}" in
  check) check ;;
  import)
    [ "$#" -eq 2 ] || { usage; exit 2; }
    import_feed "$2" ;;
  update)
    [ "$#" -eq 2 ] || { usage; exit 2; }
    case "$2" in http://*|https://*) :;; *) fail 'Feed URL must start with http(s)://';; esac
    have_tool curl || fail 'curl required for feed download'
    mkdir -p "$WORK"
    trap 'cleanup' 0 1 2 3 15
    say "Downloading $2"
    curl -f -L -s -S --connect-timeout 10 --max-time 90 -o "$WORK/stations.m3u" "$2" || fail 'Download failed; existing stations unchanged'
    import_feed "$WORK/stations.m3u" ;;
  refresh|reload) [ "$#" -le 2 ] || fail 'Usage: refresh [port]'; refresh_ushare "${2:-}" ;;
  *) usage; [ "$#" -eq 0 ] || exit 2 ;;
esac