#!/bin/sh
# Exact structure observed in the saved boot-launcher backup.
# Not intended as a station refresh command: it runs remote-m3u too.
grep -q " /mnt/ramfs/var/data jffs2 " /proc/mounts || mount -t jffs2 /dev/mtdblock/5 /mnt/ramfs/var/data
/opt/bin/remote-m3u /opt/etc/remote-m3u.conf
/opt/bin/ushare -f /opt/etc/ushare.conf &
