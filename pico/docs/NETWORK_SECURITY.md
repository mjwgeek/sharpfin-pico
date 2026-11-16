# Isolating legacy open Wi-Fi with OpenWrt

The tested Revo Pico's original RT73 firmware **did not demonstrate a working WPA2 four-way handshake**. An open SSID may be an acceptable temporary compatibility option if properly segmented.

## Recommended principles

- Create a separate 2.4 GHz guest SSID, isolated interface/subnet and firewall zone. Preserve the Pico's known working connection during any network change.
- Allow DHCP and DNS on the router and internet access for radio streaming.
- **Deny access from that guest zone to the trusted LAN and any other private subnets.** If OpenWrt is behind an upstream home router, guest-to-WAN forwarding alone may expose that upstream LAN; block those private routes explicitly.
- Enable **Isolate Clients** to stop clients on the same SSID talking to one another. This does **not** isolate them from the rest of the network by itself.
- MAC filtering is not strong security; MAC addresses can be observed and spoofed.
- Keep selective, firewall-limited management exceptions only where needed. Telnet sends credentials and shell traffic in plaintext; avoid exposing it on an open network.
- Don't publish device-specific SSIDs, passphrases, private NAND configuration or personal network topology in public example files.

HTTPS modern directory fetches occur **on the PHP host**. Audio on HTTP and management over Telnet are unencrypted.
