#!/bin/sh
set -e

REPO="necronicle/z24k"
RAW_BASE="https://raw.githubusercontent.com/$REPO/master"
NO_CACHE="${NO_CACHE:-$(date +%s)}"
TMP="/tmp/z24k"

if command -v curl >/dev/null 2>&1; then
	curl -fsSL "$RAW_BASE/z24k?nocache=$NO_CACHE" -o "$TMP"
elif command -v wget >/dev/null 2>&1; then
	wget -qO "$TMP" "$RAW_BASE/z24k?nocache=$NO_CACHE"
else
	echo "curl or wget is required" >&2
	exit 1
fi

chmod +x "$TMP"
exec "$TMP"
