# Daily operations and scheduling

## Refresh the server and Pico

The existing server-side job writes the public static M3U file:

~~~sh
/usr/local/sbin/reciva-update-feed.sh
curl -fS http://reciva.wg5eek.com/stations.m3u -o /tmp/published.m3u
wc -c /tmp/published.m3u
~~~

The Pico's **persistent** updater handles download, change detection, import and uShare-only restart:

~~~sh
sh /mnt/ramfs/var/data/PicoStationDirectory/pico_auto_update_v1.sh check
sh /mnt/ramfs/var/data/PicoStationDirectory/pico_auto_update_v1.sh update
~~~

It checks that mtd5 is mounted, downloads HTTP M3U data, verifies structure, compares with `last_imported_feed.m3u`, installs genre folders if changed, restarts *only* uShare and saves the successful feed.

If you already manually imported the feed without using the auto-updater, the next auto-update might import the same data once more because the saved comparison file is still old.

## uShare-only refresh

On the tested Pico, `/opt/etc/ushare.conf` contains:

~~~ini
USHARE_NAME=Browse radio
USHARE_IFACE=lo
USHARE_PORT=49152
USHARE_DIR=/opt/Stations
ENABLE_WEB=no
ENABLE_TELNET=no
ENABLE_DLNA=no
~~~

The uShare CGI control endpoint is disabled, so **do not** run the importer's `refresh` command (it attempts `web/ushare.cgi`). In particular, port **1337 is not the configured uShare port**.

The previously tested manual refresh restarts *only* the UPnP server:

~~~sh
killall ushare
/opt/bin/ushare -f /opt/etc/ushare.conf &
ps | grep '[u]share'
~~~

This briefly interrupts UPnP playback and browsing. It does **not** restart `/root/ir` or Wi-Fi. The automatic updater already performs the equivalent restart when its feed changes. Do not run the saved `run_ushare.sh` boot script just to rebuild the index; that invokes `remote-m3u` as well.

## Existing scheduled job

The radio already has a working cron-like setup with:

~~~text
/mnt/ramfs/var/data/PicoStationDirectory/pico_auto_update_v1.sh
/mnt/ramfs/var/data/PicoStationDirectory/auto_schedule.sh
~~~

The exact contents of `auto_schedule.sh` and the crontab were **not provided**, so don't install another job over them or silently change their frequency. Inspect first:

~~~sh
cat /mnt/ramfs/var/data/PicoStationDirectory/auto_schedule.sh
ps | grep '[c]rond'
crontab -l
~~~

BusyBox variants can have different cron interfaces. Only on a device with **no existing schedule**, a representative crontab entry would be:

~~~text
0 */6 * * * /bin/sh /mnt/ramfs/var/data/PicoStationDirectory/pico_auto_update_v1.sh update >> /tmp/pico-auto.log 2>&1
~~~

Logs go to volatile `/tmp` to avoid constant NAND writes. Keep the server publishing schedule ahead of the radio pull schedule.

## Troubleshooting

- `wget: File exists`: old BusyBox wget does not overwrite. Download to a new temp filename and verify before replacing.
- No UPnP change after manual import: restart *only* uShare, not the main radio process.
- Import refuses mtd5 write: confirm `/mnt/ramfs/var/data` is mounted; do not redirect writes into RAM or the smaller debug partition.
- Missing genre folders: inspect the importer output and `/opt/Stations/Live_Directory` symlink.
- `https://` streams fail: regenerate server feed with PHP 0.3.1, republish static M3U, and run the Pico auto-updater.
- Some HTTP streams fail anyway: HTTPS-only, redirected, changed codec or dead streams cannot be fixed by URL rewriting.
