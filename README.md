zapret2 for Keenetic (Entware)
==============================

This repository provides a one-command installer for Keenetic routers via Entware.

Quick install (opens menu):

```
curl -O https://raw.githubusercontent.com/necronicle/z24k/master/z24k && sh z24k
```

Requirements and dependencies:
- Entware installed (mount /opt)
- Keenetic components: "IPv6 Protocol" and "Netfilter kernel modules"
- Hardware flow offload disabled in router settings
- Space: about 2.6–3.1 MB in /opt

If curl is missing:

```
apt update || opkg update && apt install curl || opkg install curl
```

If Entware package downloads hang (PKH block), apply:

```
sed -i 's|bin.entware.net|entware.diversion.ch|g' /opt/etc/opkg.conf
```

What the installer does:
- Downloads the latest zapret2 openwrt-embedded release
- Installs into /opt/zapret2
- Adds Keenetic-specific fixes (UDP mark fix + ndm netfilter hook)
- Enables autostart via /opt/etc/init.d/S90-zapret2
- Preserves your /opt/zapret2/config on reinstall
- Fetches categories, strategies, lists, and blobs for category-based rules

After install:
- Menu: run `z24k` to select strategies and manage service
- Default mode: category-based rules (categories.ini + strategies-*.ini)
- Strategy picker: "Подбор стратегий (как magisk)" with TLS 1.2/1.3 checks

Categories and strategies:
- Categories file: `/opt/zapret2/z24k-categories.ini`
- Strategies: `/opt/zapret2/z24k-strategies-tcp.ini`, `/opt/zapret2/z24k-strategies-udp.ini`, `/opt/zapret2/z24k-strategies-stun.ini`
- Blobs: `/opt/zapret2/z24k-blobs.txt` + `/opt/zapret2/files/fake/*`

RKN list mirrors:
- Set `Z24K_RKN_URLS` in `/opt/zapret2/config` to override mirrors (space-separated URLs)

If raw content looks stale (cache), use GitHub API to fetch the latest commit SHA:

```
sha=$(curl -fsSL https://api.github.com/repos/necronicle/z24k/commits/master | sed -n 's/.*"sha": *"\\([0-9a-f]\\+\\)".*/\\1/p' | head -n1)
curl -fsSL https://raw.githubusercontent.com/necronicle/z24k/$sha/z24k | sh
```
