# RT73 WPA2-AES compatibility experiments (not a fix)

**Risk:** The original Pico is reachable only by Telnet over Wi-Fi. A driver crash or lost Wi-Fi connection can permanently interrupt remote access. A timed reboot watchdog can attempt recovery but **cannot guarantee it**. Do not swap the active kernel module over Wi-Fi.

## Observations from the original device

- Familiar Linux 2.4.26 (ARM), BusyBox 1.5.1, legacy Ralink RT73 module `rt73.o`, `rt73_supplicant` helper.
- The original helper contains WPA-PSK/TKIP defaults; the experiment used a private patched helper requesting `WPA2PSK` and `AES`.
- The patched helper reported exit code 0, meaning driver-setting calls succeeded, **not** authenticated WPA2.
- On a separate 2.4 GHz SSID, the `iwconfig` samples at about **3 and 9 seconds** displayed that SSID and an AP BSSID with very strong RSSI (~-38 to -40 dBm).
- At about **6, 12, and 15 seconds**, association disappeared. This also happened with another protected SSID.
- The independently detached 15-second watchdog self-test passed, and the 60-second watchdog reached its reboot request. The radio later reconnected to the original SSID.
- No DHCP, encrypted session or application-level connectivity to the protected SSID was demonstrated.

These observations show an attempted network switch and intermittent association, not a working WPA2 connection. An obsolete handshake implementation or access-point negotiation incompatibility remains a hypothesis. A newer Ralink Linux-2.4-compatible driver source might be worth porting **offline**, not installing blindly.

## Reproducibility material

The original [v4 test script](../experiments/pico_wpa2_60s_test_v4.sh) is published for inspection. It requires a separately prepared patched ARM helper at `/tmp/rt73_supplicant_wpa2aes` and **private** test configuration at `/tmp/pico_wpa2_test.conf`. That helper's expected MD5 is baked into the test. **The helper binary is deliberately not redistributed** because it was derived from vendor firmware and its redistribution rights are unclear.

The helper prints the password to stdout; the test script explicitly discards it. It also uses `SIGSTOP`/`SIGCONT` on the main radio executable during testing, and a detached watchdog attempts an automatic reboot. Do not run it without physical access and an independent recovery plan.

Never publish original NAND partitions, device-specific PSKs, or full unsanitized logs.
