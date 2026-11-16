#!/bin/sh
# Revo Pico WiFi / Reciva RT73: experimental WPA2-AES association test.
# v4: BusyBox 1.5.1 compatible; collect multiple association snapshots; no setsid.
# Derived from v3 and syntax-checked off-device only. No persistent firmware changes.
# WARNING: Only Telnet-over-Wi-Fi access; test may lose access. An automatic
# reboot is ATTEMPTED after 60s, but not guaranteed to restore the connection.

PATH=/sbin:/bin:/usr/sbin:/usr/bin
export PATH
umask 077
SELF=$0
HELPER=/tmp/rt73_supplicant_wpa2aes
CONF=/tmp/pico_wpa2_test.conf
PASS=/tmp/pico_wpa2_v4_selftest.ok
STARTED=/tmp/pico_wpa2_v4_selftest.started
LOG=/mnt/debug/pico_wpa2_60s_result_v4.log
READY=/tmp/pico_wpa2_v4_watchdog.ready
EXPECTED_MD5='2b64b969ed3382cbdcb9f9d915e71f5d'

msg() { echo "pico-wpa2-v4: $*"; }
fail() { msg "ERROR: $*" >&2; exit 1; }

# Detached children get their terminal descriptors closed, and their parent
# launcher ignores SIGHUP before exec. They also ignore HUP here.
case "$1" in
  _selftest_child)
    trap '' HUP
    echo STARTED > "$STARTED" || exit 1
    /bin/sleep 15
    echo 'PASS: v4 15-second detached timer completed' > "$PASS"
    exit 0
    ;;
  _watchdog)
    trap '' HUP
    echo "watchdog launched, attempting reboot in 60 seconds" >> "$LOG"
    echo READY > "$READY" || exit 1
    /bin/sleep 60
    echo 'watchdog: 60 seconds elapsed; attempting reboot to restore original Wi-Fi' >> "$LOG"
    /bin/sync
    /sbin/reboot
    /bin/sleep 5
    /bin/busybox reboot -f
    exit 0
    ;;
esac

case "$SELF" in
  /*) ;;
  *) fail 'Use absolute path: sh /tmp/pico_wpa2_60s_test_v4.sh COMMAND' ;;
esac

preflight() {
  [ -x /bin/busybox ] || fail 'Missing /bin/busybox'
  [ -d /proc ] || fail 'Missing /proc'
  [ -x /sbin/iwconfig ] || fail 'Missing /sbin/iwconfig'
  [ -x /sbin/reboot ] || fail 'Missing /sbin/reboot'
  [ -f /root/ir ] || fail 'Original /root/ir absent'
  [ -r /etc/inittab ] || fail 'Cannot examine /etc/inittab'
  grep -q 'respawn:/root/autostart' /etc/inittab || fail 'Unknown init autostart; refusing test'
  [ -r /mnt/config/selected_essid ] || fail 'Existing saved Wi-Fi SSID not found'
  mount | grep -q ' /mnt/debug ' || fail 'Result partition /mnt/debug not mounted'
  [ -d /mnt/debug ] && [ -w /mnt/debug ] || fail 'Result partition unavailable for writing'
  /sbin/iwconfig wlan0 >/dev/null 2>&1 || fail 'wlan0 unavailable'
  msg 'Current wlan0 status:'
  /sbin/iwconfig wlan0 2>/dev/null || true
  msg 'No wireless or radio settings changed.'
}

verify_helper() {
  [ -x "$HELPER" ] || fail "Missing/non-executable patched helper: $HELPER"
  [ -r "$CONF" ] || fail "Missing test configuration: $CONF"
  GOT=`/usr/bin/md5sum "$HELPER" 2>/dev/null | /usr/bin/awk '{print $1}'`
  [ "$GOT" = "$EXPECTED_MD5" ] || fail 'Patched ARM helper does not match expected checksum'
  grep -q '^[[:space:]]*ssid=' "$CONF" || fail 'Test config missing ssid='
  grep -q '^[[:space:]]*psk=' "$CONF" || fail 'Test config missing psk='
  if grep -q 'YOUR_TEST' "$CONF"; then fail 'Replace placeholder test SSID/password before running'; fi
  if grep -q 'ssid="RevoPico"' "$CONF"; then fail 'Test SSID must be separate from current fallback Wi-Fi'; fi
  # Deliberately never echo the test SSID, PSK, or helper stdout.
}

find_ir_pid() {
  IRPID=
  for F in /proc/[0-9]*/cmdline; do
    if grep -q '[.]/ir' "$F" 2>/dev/null; then
      IRPID=${F#/proc/}
      IRPID=${IRPID%/cmdline}
      break
    fi
  done
  [ -n "$IRPID" ] || fail 'Cannot identify running ./ir process'
  kill -0 "$IRPID" 2>/dev/null || fail 'Main radio application no longer running'
  msg "Radio application process PID=$IRPID"
}

# Launch a child which can outlive the telnetd controlling process. This uses
# exactly the construct that passed the user's independent HUP-survival test.
launch_child() {
  KIND=$1
  ( trap '' HUP; exec /bin/sh "$SELF" "$KIND" ) </dev/null >/dev/null 2>&1 &
  CHILD_PID=$!
}

case "$1" in
  check)
    preflight
    verify_helper
    msg 'Staging checks passed.'
    ;;
  selftest)
    preflight
    rm -f "$PASS" "$STARTED"
    launch_child _selftest_child
    /bin/sleep 2
    [ -f "$STARTED" ] || fail 'Detached child did not start; do not test Wi-Fi'
    kill -0 "$CHILD_PID" 2>/dev/null || fail 'Detached child exited prematurely; do not test Wi-Fi'
    msg 'Harmless timer started. Disconnect Telnet and reconnect after 20 seconds.'
    msg 'Then run: sh /tmp/pico_wpa2_60s_test_v4.sh status'
    ;;
  status)
    if [ -f "$PASS" ]; then
      msg 'PASS: v4 detached self-test completed. It does NOT prove reboot recovery.'
    else
      msg 'NO PASS: v4 self-test has not completed; do not test Wi-Fi.'
    fi
    if [ -f "$LOG" ]; then
      msg 'Previous saved test log:'
      cat "$LOG"
    fi
    ;;
  test)
    [ "$2" = 'I_ACCEPT_WIFI_DROP_AND_REBOOT' ] || fail 'Acknowledgement missing; see script usage'
    preflight
    verify_helper
    [ -f "$PASS" ] || fail 'First run the v4 selftest and confirm PASS after Telnet reconnects'
    /sbin/iwconfig wlan0 2>/dev/null | grep -q 'ESSID:"RevoPico"' || fail 'Radio is no longer on expected RevoPico fallback SSID'
    find_ir_pid
    echo '=== Experimental WPA2-AES RT73 connection test (v4) ===' > "$LOG" || fail 'Cannot write result log'
    /bin/date >> "$LOG" 2>/dev/null
    echo 'Original connection:' >> "$LOG"
    /sbin/iwconfig wlan0 >> "$LOG" 2>&1
    rm -f "$READY"
    launch_child _watchdog
    /bin/sleep 2
    if [ ! -f "$READY" ]; then
      kill "$CHILD_PID" 2>/dev/null
      fail 'Watchdog did not signal READY; radio left running'
    fi
    kill -0 "$CHILD_PID" 2>/dev/null || fail 'Watchdog exited before the test; radio left running'
    echo "Watchdog READY; PID=$CHILD_PID, radio PID=$IRPID" >> "$LOG"
    /bin/sync
    kill -STOP "$IRPID" || fail 'Cannot suspend main application; watchdog will still attempt reboot'
    echo 'Main application suspended. Running patched helper.' >> "$LOG"
    # The helper prints the WPA password on stdout. NEVER record stdout.
    # Keep stderr separate and only log fixed, nonsecret failure messages.
    ERRFILE=/tmp/pico_wpa2_v4_helper.err
    rm -f "$ERRFILE"
    "$HELPER" -c "$CONF" -i wlan0 >/dev/null 2>"$ERRFILE"
    RC=$?
    echo "Patched helper exit code: $RC (only ioctl success; NOT WPA2 authentication)" >> "$LOG"
    if [ -s "$ERRFILE" ]; then
      echo 'Driver-setting errors (only recognized nonsecret messages):' >> "$LOG"
      grep -E '^Failed to (set|open|get) ' "$ERRFILE" >> "$LOG" 2>/dev/null || true
    fi
    rm -f "$ERRFILE"
    # Detect a brief association that later disappears; do not invoke
    # active scanning, DHCP, or additional driver-setting commands.
    ELAPSED=0
    while [ "$ELAPSED" -lt 15 ]; do
      /bin/sleep 3
      ELAPSED=$((ELAPSED + 3))
      echo "--- wlan0 at approximately ${ELAPSED}s after helper ---" >> "$LOG"
      /sbin/iwconfig wlan0 >> "$LOG" 2>&1
    done
    echo 'Wireless counters following attempt:' >> "$LOG"
    cat /proc/net/wireless >> "$LOG" 2>/dev/null
    /sbin/iwpriv wlan0 stat >> "$LOG" 2>&1
    echo 'Resuming main radio application. Reboot watchdog remains armed.' >> "$LOG"
    kill -CONT "$IRPID" 2>/dev/null
    /bin/sync
    msg 'Test attempted. A separate timer should request a reboot at 60 seconds.'
    msg 'After reconnecting: cat /mnt/debug/pico_wpa2_60s_result_v4.log'
    ;;
  *)
    cat <<'HELP'
Usage:
  sh /tmp/pico_wpa2_60s_test_v4.sh check
  sh /tmp/pico_wpa2_60s_test_v4.sh selftest
  sh /tmp/pico_wpa2_60s_test_v4.sh status
  sh /tmp/pico_wpa2_60s_test_v4.sh test I_ACCEPT_WIFI_DROP_AND_REBOOT

Do not run test until the v4 selftest passes after a Telnet disconnect AND
an ordinary reboot is known to restore the existing RevoPico Wi-Fi network.
A successful timer is not proof of recovery; Wi-Fi-only access may be lost.
The script does not save a new network or run DHCP. Do not share the secret
file /tmp/pico_wpa2_test.conf. The patched helper prints secrets to stdout,
which this script discards. Use a separate WPA2-Personal/AES 2.4 GHz SSID.
HELP
    ;;
esac