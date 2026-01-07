zapret2 for Keenetic (Entware)
==============================

This repository provides a one-command installer for Keenetic routers via Entware.

Quick install (opens menu):

```
curl -fsSL https://github.com/necronicle/z24k/raw/master/install.sh | sh
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
- Menu: run `z24k` to select strategies and manage service

Alternate entrypoint (same behavior):

```
curl -fsSL https://raw.githubusercontent.com/necronicle/z24k/master/keenetic/install.sh | sh
```

If raw content looks stale (cache), use GitHub API to fetch the latest commit SHA:

```
sha=$(curl -fsSL https://api.github.com/repos/necronicle/z24k/commits/master | sed -n 's/.*"sha": *"\\([0-9a-f]\\+\\)".*/\\1/p' | head -n1)
curl -fsSL https://raw.githubusercontent.com/necronicle/z24k/$sha/install.sh | sh
```
