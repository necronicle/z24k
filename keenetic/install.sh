#!/bin/sh
set -e

REPO_INSTALL_URL="https://raw.githubusercontent.com/necronicle/z24k/master/install.sh"

if command -v curl >/dev/null 2>&1; then
	exec sh -c "curl -fsSL \"$REPO_INSTALL_URL\" | sh"
elif command -v wget >/dev/null 2>&1; then
	exec sh -c "wget -qO- \"$REPO_INSTALL_URL\" | sh"
else
	echo "curl or wget is required" >&2
	exit 1
fi
