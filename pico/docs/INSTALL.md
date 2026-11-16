# Installation and first station update

**Scope:** Legacy-compatible internet radio lists via Sharpfin uShare, not a firmware patch. Keep an independently recoverable Wi-Fi connection. Never overwrite a working installation without backing it up.

## 1. Host the PHP bridge on Linux

Requirements: PHP 7.4 or newer, PHP cURL, outbound HTTPS with normal TLS certificate validation, writable PHP temp cache, and enough execution time for first generation across 65 tags. Optional PHP XMLReader + SimpleXML enable `?source=xiph`.

Copy [../server/php_feed.php](../server/php_feed.php) into the HTTP document root **as `php_feed.php`**. On the tested server this appears as:

~~~text
http://reciva.wg5eek.com/php_feed.php
~~~

Generate and inspect the output on your server:

~~~sh
php -l /path/to/webroot/php_feed.php
curl -fS 'http://reciva.wg5eek.com/php_feed.php?source=radio&country=US' -o /tmp/stations-test.m3u
head -n 5 /tmp/stations-test.m3u
wc -c /tmp/stations-test.m3u
grep -c '^https://' /tmp/stations-test.m3u
~~~

The last count should be `0`; first generation may take time. Feed data must stay below 300 KB. All output stream URLs use HTTP, but not every station necessarily supports HTTP.

The actual server already runs `/usr/local/sbin/reciva-update-feed.sh`, with observed `SOURCE=http://reciva.wg5eek.com/php_feed.php` and `DEST=$WEBROOT/stations.m3u`. Preserve that working script. An independently usable **example** is [../server/reciva-update-feed.example.sh](../server/reciva-update-feed.example.sh); set `WEBROOT` to the actual web root when using the example. The static output should be available at:

~~~text
http://reciva.wg5eek.com/stations.m3u
~~~

Use the installed publisher, then inspect the static file:

~~~sh
/usr/local/sbin/reciva-update-feed.sh
curl -fS http://reciva.wg5eek.com/stations.m3u -o /tmp/published.m3u
wc -c /tmp/published.m3u
grep -c '^https://' /tmp/published.m3u
~~~

## 2. Pico prerequisites and persistence

The tested radio runs Familiar Linux 2.4.26, BusyBox 1.5.1. It has only Telnet over Wi-Fi; do not edit `/root/ir`, the current wireless configuration, or the system boot launcher as part of station setup.

Read-only checks:

~~~sh
cat /proc/mounts
df -k /tmp /mnt/ramfs/var/data
ls -ld /opt/Stations /mnt/ramfs/var/data/PicoStationDirectory
cat /opt/etc/ushare.conf
ps | grep '[u]share'
~~~

Station library and scripts live on the **16 MiB mtd5 JFFS2** mount:

~~~text
/mnt/ramfs/var/data/PicoStationDirectory/
  Live_Directory/
  pico_station_refresh_v03.sh
  pico_auto_update_v1.sh
  last_imported_feed.m3u
  auto_schedule.sh
~~~

The installed `pico_station_refresh_v03.sh` has **v0.5** logic: we retained its original deployed filename so the auto-updater can find it. An existing `auto_schedule.sh` is device-specific; its exact content wasn't captured here and must not be overwritten.

On a new radio, transfer the two device scripts from [../device](../device/) via a trusted local HTTP server. The old BusyBox `wget -O` **will not overwrite existing files**. Always download to new names under `/tmp`, inspect file sizes, and keep backups before installing copies to mtd5. Verify the importer with:

~~~sh
sh /mnt/ramfs/var/data/PicoStationDirectory/pico_station_refresh_v03.sh check
~~~

## 3. Update the station list

Prefer the persistent auto-updater. It fetches the static file, checks for changes, imports genre folders, restarts uShare if needed and updates its last-imported state:

~~~sh
sh /mnt/ramfs/var/data/PicoStationDirectory/pico_auto_update_v1.sh check
sh /mnt/ramfs/var/data/PicoStationDirectory/pico_auto_update_v1.sh update
~~~

For manual import only (does not update the auto-updater's comparison state):

~~~sh
sh /mnt/ramfs/var/data/PicoStationDirectory/pico_station_refresh_v03.sh update 'http://reciva.wg5eek.com/stations.m3u'
~~~

Validate the result:

~~~sh
ls /mnt/ramfs/var/data/PicoStationDirectory/Live_Directory/
find /mnt/ramfs/var/data/PicoStationDirectory/Live_Directory -name Stations.m3u | wc -l
ls -ld /opt/Stations/Live_Directory
~~~

The tested result contained **80 genre folders** (e.g., `Rock_2`, `Jazz_3`, `Christian_3`). Open **Media Player → UPnP → Browse radio** on the Pico. A manual import without the auto-update wrapper may require the safe uShare-only restart documented in [OPERATIONS.md](OPERATIONS.md). Do not run the full boot launcher just to refresh UPnP.
