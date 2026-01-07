#!/bin/sh
set -e

SCRIPT_VERSION="2026-01-07-5"
Z24K_RAW="https://github.com/necronicle/z24k/raw/master"
TMP_MENU="/tmp/z24k.sh"

if command -v curl >/dev/null 2>&1; then
	curl -fsSL "$Z24K_RAW/z24k.sh" -o "$TMP_MENU"
elif command -v wget >/dev/null 2>&1; then
	wget -qO "$TMP_MENU" "$Z24K_RAW/z24k.sh"
else
	echo "curl or wget is required" >&2
	exit 1
fi

chmod +x "$TMP_MENU"
exec "$TMP_MENU"
