# Architecture and persistence

~~~text
Radio Browser / Xiph YP (HTTPS on modern PHP server)
       ↓
php_feed.php: 65 genre tags, MP3 <= 128 kbps, 6h cache
       ↓
static stations.m3u over HTTP (< 300KB; stream URLs rewritten HTTP)
       ↓
Revo Pico: pico_auto_update_v1.sh (BusyBox shell, cURL)
       ↓  compare with last_imported_feed.m3u
pico_station_refresh_v03.sh (v0.5 importer)
       ↓
mtd5 JFFS2: /mnt/ramfs/var/data/PicoStationDirectory/
  Live_Directory/
    Rock/Stations.m3u
    Rock_2/Stations.m3u
    Jazz/Stations.m3u
    ...
       ↓
/opt/Stations/Live_Directory -> persistent Live_Directory
       ↓
uShare: /opt/bin/ushare -f /opt/etc/ushare.conf
  loopback interface; port 49152; web controls disabled
       ↓
Radio menu: Media Player → UPnP → Browse radio
~~~

## Why this architecture?

The radio's ancient TLS implementation fails on some modern HTTPS streams and directory APIs. A modern server performs HTTPS directory lookups and exposes a static HTTP M3U. Individual audio URLs are rewritten to HTTP, which only helps when their origins support plain HTTP.

The radio's `/tmp` is temporary; the **16 MiB mtd5 JFFS2 partition** persists the genre library. It is not additional RAM and should not be used as high-write-rate swap or audio buffering. The native Reciva Stations menu and other favorites are not intentionally rewritten.

The PHP feed limits every numbered folder to **40 stations**; the importer has an independent **50-station** folder limit and converts spaces in names to underscores. The observed expanded library created **80 folders** from a roughly **126 KB** feed, but this count is not guaranteed for future updates.

The server publisher example is not a bit-for-bit capture of the user's installed server script. Similarly, the device-local scheduler script was seen on mtd5 but was not captured in this repository.
