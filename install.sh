#!/bin/sh
set -e

SCRIPT_VERSION="2026-01-07-1"
DEFAULT_VER="0.8.2"
REPO="bol-van/zapret2"
KEENETIC_REPO_RAW="https://raw.githubusercontent.com/necronicle/z24k/master/keenetic"
INSTALL_DIR="/opt/zapret2"
TMP_DIR="/tmp/zapret2-install"

export PATH="/opt/bin:/opt/sbin:$PATH"

log() {
	echo "[zapret2] $*"
}

need_cmd() {
	command -v "$1" >/dev/null 2>&1
}

fetch() {
	url="$1"
	out="$2"

	if need_cmd curl; then
		curl -fsSL "$url" -o "$out"
	elif need_cmd wget; then
		wget -qO "$out" "$url"
	else
		echo "curl or wget is required" >&2
		exit 1
	fi
}

get_latest_ver() {
	api="https://api.github.com/repos/$REPO/releases/latest"
	ver=""

	if need_cmd curl; then
		ver=$(curl -fsSL "$api" | sed -n 's/.*"tag_name": *"v\([0-9.]*\)".*/\1/p' | head -n1)
	elif need_cmd wget; then
		ver=$(wget -qO- "$api" | sed -n 's/.*"tag_name": *"v\([0-9.]*\)".*/\1/p' | head -n1)
	fi

	if [ -n "$ver" ]; then
		echo "$ver"
	else
		echo "$DEFAULT_VER"
	fi
}

backup_config() {
	if [ -f "$INSTALL_DIR/config" ]; then
		mkdir -p "$TMP_DIR"
		cp -f "$INSTALL_DIR/config" "$TMP_DIR/config.bak"
	fi
}

restore_config() {
	if [ -f "$TMP_DIR/config.bak" ]; then
		cp -f "$TMP_DIR/config.bak" "$INSTALL_DIR/config"
	fi
}

set_ws_user() {
	config="$INSTALL_DIR/config"
	bin="$INSTALL_DIR/nfq2/nfqws2"

	[ -f "$config" ] || return 0
	grep -q '^#WS_USER=' "$config" || return 0
	[ -x "$bin" ] || return 0

	if "$bin" --dry-run --user=nobody 2>&1 | grep -q queue; then
		sed -i 's/^#WS_USER=.*/WS_USER=nobody/' "$config"
		return 0
	fi

	user=$(awk -F: 'NR==1{print $1}' /etc/passwd 2>/dev/null || true)
	if [ -n "$user" ] && "$bin" --dry-run --user="$user" 2>&1 | grep -q queue; then
		sed -i "s/^#WS_USER=.*/WS_USER=$user/" "$config"
	fi
}

install_extras() {
	log "Fetching Keenetic extras from $KEENETIC_REPO_RAW"
	mkdir -p /opt/etc/ndm/netfilter.d /opt/etc/init.d
	mkdir -p "$INSTALL_DIR/init.d/sysv/custom.d"

	fetch "$KEENETIC_REPO_RAW/000-zapret2.sh" /opt/etc/ndm/netfilter.d/000-zapret2.sh
	chmod +x /opt/etc/ndm/netfilter.d/000-zapret2.sh

	fetch "$KEENETIC_REPO_RAW/S00fix" /opt/etc/init.d/S00fix
	chmod +x /opt/etc/init.d/S00fix

	fetch "$KEENETIC_REPO_RAW/zapret2" "$INSTALL_DIR/init.d/sysv/zapret2"
	chmod +x "$INSTALL_DIR/init.d/sysv/zapret2"

	cp -f "$INSTALL_DIR/init.d/custom.d.examples.linux/10-keenetic-udp-fix" \
		"$INSTALL_DIR/init.d/sysv/custom.d/10-keenetic-udp-fix"

	ln -sf "$INSTALL_DIR/init.d/sysv/zapret2" /opt/etc/init.d/S90-zapret2
}

install_release() {
	ver="$1"
	tarball="zapret2-v${ver}-openwrt-embedded.tar.gz"
	url="https://github.com/$REPO/releases/download/v$ver/$tarball"

	rm -rf "$TMP_DIR"
	mkdir -p "$TMP_DIR"

	log "Downloading $tarball"
	fetch "$url" "$TMP_DIR/$tarball"
	tar -xzf "$TMP_DIR/$tarball" -C "$TMP_DIR"

	src="$TMP_DIR/zapret2-v$ver"
	if [ ! -d "$src" ]; then
		src=$(find "$TMP_DIR" -maxdepth 1 -type d -name "zapret2-v*" | head -n1)
	fi

	[ -d "$src" ] || {
		echo "Cannot find extracted directory" >&2
		exit 1
	}

	rm -rf "$INSTALL_DIR"
	mv "$src" "$INSTALL_DIR"
}

main() {
	log "Installer version $SCRIPT_VERSION"
	if [ ! -d /opt ]; then
		echo "/opt is required (Entware). Install Entware first." >&2
		exit 1
	fi

	if [ -x "$INSTALL_DIR/init.d/sysv/zapret2" ]; then
		"$INSTALL_DIR/init.d/sysv/zapret2" stop || true
	fi

	backup_config

	ver=$(get_latest_ver)
	log "Using version $ver"
	install_release "$ver"

	if [ ! -f "$INSTALL_DIR/config" ]; then
		cp -f "$INSTALL_DIR/config.default" "$INSTALL_DIR/config"
	fi

	sh "$INSTALL_DIR/install_bin.sh"
	restore_config
	set_ws_user
	install_extras

	if [ -x /opt/etc/init.d/S00fix ]; then
		/opt/etc/init.d/S00fix start || true
	fi

	"$INSTALL_DIR/init.d/sysv/zapret2" restart
	log "Done. Edit $INSTALL_DIR/config if needed."
}

main "$@"
