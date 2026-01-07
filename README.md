zapret2 for Keenetic (Entware)
==============================

This repository provides a one-command installer for Keenetic routers via Entware.

Quick install:

```
curl -fsSL https://raw.githubusercontent.com/necronicle/z24k/master/install.sh | sh
```

Requirements:
- Entware installed (mount /opt)
- Keenetic components: "IPv6 Protocol" and "Netfilter kernel modules"
- Hardware flow offload disabled in router settings

What the installer does:
- Downloads the latest zapret2 openwrt-embedded release
- Installs into /opt/zapret2
- Adds Keenetic-specific fixes (UDP mark fix + ndm netfilter hook)
- Enables autostart via /opt/etc/init.d/S90-zapret2
- Preserves your /opt/zapret2/config on reinstall

After install:
- Edit /opt/zapret2/config if needed (enable NFQWS2, change ports, lists, etc.)
- Restart: /opt/zapret2/init.d/sysv/zapret2 restart

Alternate entrypoint (same behavior):

```
curl -fsSL https://raw.githubusercontent.com/necronicle/z24k/master/keenetic/install.sh | sh
```
