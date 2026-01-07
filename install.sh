#!/bin/sh
set -e

SCRIPT_VERSION="2026-01-07-6"
REPO="necronicle/z24k"
RAW_BASE="https://raw.githubusercontent.com/$REPO"
RAW_FALLBACK="https://github.com/$REPO/raw/master"
TMP_MENU="/tmp/z24k.sh"

fetch() {
	url="$1"
	out="$2"
	if command -v curl >/dev/null 2>&1; then
		curl -fsSL "$url" -o "$out"
	elif command -v wget >/dev/null 2>&1; then
		wget -qO "$out" "$url"
	else
		echo "curl or wget is required" >&2
		exit 1
	fi
}

get_sha() {
	if command -v curl >/dev/null 2>&1; then
		curl -fsSL "https://api.github.com/repos/$REPO/commits/master" | \
			sed -n 's/.*"sha": *"\\([0-9a-f]\\+\\)".*/\\1/p' | head -n1
	elif command -v wget >/dev/null 2>&1; then
		wget -qO- "https://api.github.com/repos/$REPO/commits/master" | \
			sed -n 's/.*"sha": *"\\([0-9a-f]\\+\\)".*/\\1/p' | head -n1
	fi
}

SHA=$(get_sha || true)
if [ -n "$SHA" ]; then
	fetch "$RAW_BASE/$SHA/z24k.sh" "$TMP_MENU" || SHA=""
fi
if [ -z "$SHA" ]; then
	fetch "$RAW_FALLBACK/z24k.sh" "$TMP_MENU"
fi

chmod +x "$TMP_MENU"
if [ -r /dev/tty ]; then
	exec "$TMP_MENU" </dev/tty
else
	exec "$TMP_MENU"
fi
