# Revo Pico preservation toolkit

Working extensions and research for an original **Revo Pico WiFi / Reciva / Sharpfin** radio, developed in November 2026. The original Sharpfin project remains untouched. This is **not** a firmware upgrade.

The station directory is available through **Media Player → UPnP → Browse radio**, not through the native Reciva Stations menu.

## What works

- A PHP 7.4+ bridge fetches Radio Browser or Icecast over modern HTTPS, filters for MP3 at up to 128 kbps, and exports a legacy-compatible M3U file.
- Version **0.3.1** exports station URLs as **HTTP**, avoiding the radio's failing TLS stack. HTTPS-only streams may still fail.
- **65 genres** are queried. Each contains up to 40 stations per numbered folder, such as `Rock`, `Rock_2`, `Rock_3`. The total cap is 1,900 stations and 275 KB per feed.
- On a tested Pico, a refreshed feed generated **80 genre folders** on the persistent 16 MiB mtd5 filesystem. Counts depend on directory availability.
- The Pico-side auto-updater compares the new static feed with its last saved copy, imports changes, restarts **only uShare**, and stores its new comparison state.
- The tested uShare uses `USHARE_PORT=49152`, `ENABLE_WEB=no`; its web refresh CGI is **not** available.
- A guarded experimental RT73 WPA2 test observed brief associations but **did not demonstrate WPA2 authentication**.

## Files

| File | Purpose |
| --- | --- |
| [server/php_feed.php](server/php_feed.php) | Current PHP 0.3.1 feed bridge |
| [server/reciva-update-feed.example.sh](server/reciva-update-feed.example.sh) | Reference static-feed publisher, **not** the exact installed server script |
| [device/pico_station_refresh_v03.sh](device/pico_station_refresh_v03.sh) | Genre importer v0.5, kept under the installed v03 filename |
| [device/pico_auto_update_v1.sh](device/pico_auto_update_v1.sh) | Tested compare/import/uShare restart wrapper |
| [device/run_ushare.example.sh](device/run_ushare.example.sh) | Saved boot-launcher reference; do **not** run it to refresh stations |
| [experiments/pico_wpa2_60s_test_v4.sh](experiments/pico_wpa2_60s_test_v4.sh) | Experimental risk-bearing WPA2 test, requires a private helper |

## Documentation

[Installation](docs/INSTALL.md) · [Operations and scheduling](docs/OPERATIONS.md) · [Architecture](docs/ARCHITECTURE.md) · [OpenWrt network isolation](docs/NETWORK_SECURITY.md) · [WPA2 research](docs/WPA2_EXPERIMENTS.md) · [Changelog](CHANGELOG.md)

**Security and provenance:** No NAND dumps, Wi-Fi credentials, personally identifying log captures, firmware images, or patched vendor binaries are included. Keep these private. See the project-wide license and existing Sharpfin attribution.
