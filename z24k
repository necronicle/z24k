#!/bin/sh
set -e

SCRIPT_VERSION="2026-01-07-94"
DEFAULT_VER="0.8.2"
REPO="bol-van/zapret2"
Z24K_REPO="necronicle/z24k"
Z24K_RAW="https://raw.githubusercontent.com/$Z24K_REPO/master"
KEENETIC_RAW="$Z24K_RAW/keenetic"
LISTS_RAW="$Z24K_RAW/lists"
CAT_RAW="$Z24K_RAW/categories.ini"
TCP_RAW="$Z24K_RAW/strategies-tcp.ini"
UDP_RAW="$Z24K_RAW/strategies-udp.ini"
STUN_RAW="$Z24K_RAW/strategies-stun.ini"
BLOBS_RAW="$Z24K_RAW/blobs.txt"
INSTALL_DIR="/opt/zapret2"
TMP_DIR="/tmp/zapret2-install"
LISTS_DIR="$INSTALL_DIR/ipset"
PKT_OUT=10

CONFIG="$INSTALL_DIR/config"
CONFIG_DEFAULT="$INSTALL_DIR/config.default"
SERVICE="$INSTALL_DIR/init.d/sysv/zapret2"
CATEGORIES_FILE="$INSTALL_DIR/z24k-categories.ini"
STRAT_TCP_FILE="$INSTALL_DIR/z24k-strategies-tcp.ini"
STRAT_UDP_FILE="$INSTALL_DIR/z24k-strategies-udp.ini"
STRAT_STUN_FILE="$INSTALL_DIR/z24k-strategies-stun.ini"
BLOBS_FILE="$INSTALL_DIR/z24k-blobs.txt"

plain='\033[0m'
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
cyan='\033[0;36m'

if [ "${Z24K_BOOTSTRAP:-0}" != "1" ] && [ "${Z24K_SELF_UPDATE:-1}" -eq 1 ]; then
	if [ "$0" != "$INSTALL_DIR/z24k.sh" ]; then
		tmp="${TMPDIR:-/tmp}/z24k.latest"
		if command -v curl >/dev/null 2>&1; then
			if curl -fsSL "$Z24K_RAW/z24k?nocache=$(date +%s)" -o "$tmp"; then
				chmod +x "$tmp"
				Z24K_BOOTSTRAP=1 exec "$tmp" "$@"
			fi
		elif command -v wget >/dev/null 2>&1; then
			if wget -qO "$tmp" "$Z24K_RAW/z24k?nocache=$(date +%s)"; then
				chmod +x "$tmp"
				Z24K_BOOTSTRAP=1 exec "$tmp" "$@"
			fi
		fi
	fi
fi

log() {
	echo "[z24k] $*"
}

pick_tmpdir() {
	if [ -n "$TMPDIR" ] && [ -w "$TMPDIR" ]; then
		echo "$TMPDIR"
	elif [ -w /tmp ]; then
		echo /tmp
	else
		echo /opt/tmp
	fi
}

read_tty() {
	if [ -r /dev/tty ]; then
		read -r -p "$1" "$2" </dev/tty || true
	else
		read -r -p "$1" "$2" || true
	fi
}

pause_enter() {
	read_tty "Enter для продолжения" _
}

safe_clear() {
	if command -v clear >/dev/null 2>&1; then
		clear || true
	fi
}

menu_item() {
	echo -e "${green}$1. $2${plain} $3"
}

need_cmd() {
	command -v "$1" >/dev/null 2>&1
}

fetch() {
	url="$1"
	out="$2"

	if need_cmd curl; then
		if ! curl -fsSL --connect-timeout 10 --max-time 60 --retry 3 "$url" -o "$out"; then
			echo -e "${yellow}Download failed: $url${plain}"
			return 1
		fi
	elif need_cmd wget; then
		if ! wget -qO "$out" --dns-timeout=10 --connect-timeout=10 --read-timeout=60 "$url"; then
			echo -e "${yellow}Download failed: $url${plain}"
			return 1
		fi
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

set_kv() {
	key="$1"
	val="$2"
	if grep -q "^${key}=" "$CONFIG" 2>/dev/null; then
		sed -i "s|^${key}=.*|${key}=${val}|" "$CONFIG"
	else
		echo "${key}=${val}" >> "$CONFIG"
	fi
}

get_kv() {
	key="$1"
	grep "^${key}=" "$CONFIG" 2>/dev/null | tail -n1 | cut -d= -f2-
}

set_mode_hostlist() {
	set_kv MODE_FILTER hostlist
}

get_opt_block() {
	file="$1"
	awk '
		/^NFQWS2_OPT="/ {in=1; next}
		in && /^"$/ {exit}
		in {print}
	' "$file"
}

set_opt_block() {
	opt="$1"
	found=0
	in_block=0
	tmp="${CONFIG}.tmp"
	: > "$tmp"
	while IFS= read -r line; do
		if [ "$in_block" -eq 1 ]; then
			[ "$line" = "\"" ] && in_block=0
			continue
		fi
		if [ "$line" = "NFQWS2_OPT=\"" ]; then
			found=1
			in_block=1
			{
				echo "NFQWS2_OPT=\""
				printf "%s\n" "$opt"
				echo "\""
			} >> "$tmp"
			continue
		fi
		echo "$line" >> "$tmp"
	done < "$CONFIG"

	if [ "$found" -eq 0 ]; then
		{
			echo ""
			echo "NFQWS2_OPT=\""
			printf "%s\n" "$opt"
			echo "\""
		} >> "$tmp"
	fi

	mv "$tmp" "$CONFIG"
}

restart_service() {
	if [ -x "$SERVICE" ]; then
		"$SERVICE" restart
	else
		echo "Service not found: $SERVICE" >&2
	fi
}

backup_config() {
	if [ -f "$CONFIG" ]; then
		mkdir -p "$TMP_DIR"
		cp -f "$CONFIG" "$TMP_DIR/config.bak"
		echo "1"
	else
		echo "0"
	fi
}

restore_config() {
	if [ -f "$TMP_DIR/config.bak" ]; then
		cp -f "$TMP_DIR/config.bak" "$CONFIG"
	fi
}

save_config_snapshot() {
	[ -f "$CONFIG" ] || return 0
	mkdir -p "$TMP_DIR"
	cp -f "$CONFIG" "$TMP_DIR/config.snapshot"
}

restore_config_snapshot() {
	if [ -f "$TMP_DIR/config.snapshot" ]; then
		cp -f "$TMP_DIR/config.snapshot" "$CONFIG"
	fi
}

set_ws_user() {
	bin="$INSTALL_DIR/nfq2/nfqws2"

	[ -f "$CONFIG" ] || return 0
	grep -q '^#WS_USER=' "$CONFIG" || return 0
	[ -x "$bin" ] || return 0

	if "$bin" --dry-run --user=nobody 2>&1 | grep -q queue; then
		sed -i 's/^#WS_USER=.*/WS_USER=nobody/' "$CONFIG"
		return 0
	fi

	user=$(awk -F: 'NR==1{print $1}' /etc/passwd 2>/dev/null || true)
	if [ -n "$user" ] && "$bin" --dry-run --user="$user" 2>&1 | grep -q queue; then
		sed -i "s/^#WS_USER=.*/WS_USER=$user/" "$CONFIG"
	fi
}

install_menu() {
	log "Installing menu"
	mkdir -p "$INSTALL_DIR" /opt/bin
	if [ -f "$0" ]; then
		cp -f "$0" "$INSTALL_DIR/z24k.sh"
	else
		fetch "$Z24K_RAW/z24k" "$INSTALL_DIR/z24k.sh"
	fi
	if [ ! -f "$INSTALL_DIR/z24k.sh" ]; then
		echo "Failed to install menu script" >&2
		return 1
	fi
	chmod +x "$INSTALL_DIR/z24k.sh"
	ln -sf "$INSTALL_DIR/z24k.sh" /opt/bin/z24k
}

install_extras() {
	log "Fetching Keenetic extras"
	mkdir -p /opt/etc/ndm/netfilter.d /opt/etc/init.d
	mkdir -p "$INSTALL_DIR/init.d/sysv/custom.d"

	fetch "$KEENETIC_RAW/000-zapret2.sh" /opt/etc/ndm/netfilter.d/000-zapret2.sh
	chmod +x /opt/etc/ndm/netfilter.d/000-zapret2.sh

	fetch "$KEENETIC_RAW/S00fix" /opt/etc/init.d/S00fix
	chmod +x /opt/etc/init.d/S00fix

	fetch "$KEENETIC_RAW/zapret2" "$INSTALL_DIR/init.d/sysv/zapret2"
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

do_install() {
	if [ ! -d /opt ]; then
		echo "/opt is required (Entware). Install Entware first." >&2
		return 1
	fi

	if [ -x "$SERVICE" ]; then
		"$SERVICE" stop || true
	fi

	HAD_CONFIG=$(backup_config)
	ver=$(get_latest_ver)
	log "Using version $ver"
	install_release "$ver"

	if [ ! -f "$CONFIG" ]; then
		cp -f "$CONFIG_DEFAULT" "$CONFIG"
	fi

	sh "$INSTALL_DIR/install_bin.sh"
	restore_config
	set_ws_user
	install_extras
	install_menu

	ensure_category_files
	sync_all_lists
	ensure_blob_files
	if ! required_lists_ok; then
		echo -e "${yellow}Списки не найдены или пустые после обновления. Автоподбор будет пропущен.${plain}"
	fi

	if [ "$HAD_CONFIG" -eq 0 ]; then
		sed -i 's/^NFQWS2_ENABLE=0/NFQWS2_ENABLE=1/' "$CONFIG"
		set_kv Z24K_PRESET categories
		set_mode_hostlist
		set_opt_block "$(preset_categories)"
	fi

	if [ -x /opt/etc/init.d/S00fix ]; then
		/opt/etc/init.d/S00fix start || true
	fi

	"$SERVICE" restart
	if required_lists_ok; then
		auto_pick_all_categories
	fi
	log "Install complete."
	pause_enter
	return 0
}

preset_default() {
	if [ -f "$CONFIG_DEFAULT" ]; then
		opt=$(get_opt_block "$CONFIG_DEFAULT" 2>/dev/null || true)
		if [ -n "$opt" ]; then
			printf "%s\n" "$opt"
			return
		fi
	else
		cat <<'EOF'
--filter-tcp=80 --filter-l7=http <HOSTLIST> --payload=http_req --lua-desync=fake:blob=fake_default_http:tcp_md5 --lua-desync=multisplit:pos=method+2 --new
--filter-tcp=443 --filter-l7=tls <HOSTLIST> --payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls:tcp_md5:tcp_seq=-10000 --lua-desync=multidisorder:pos=1,midsld --new
--filter-udp=443 --filter-l7=quic <HOSTLIST_NOAUTO> --payload=quic_initial --lua-desync=fake:blob=fake_default_quic:repeats=6
EOF
	fi
}

preset_manual() {
	cat <<'EOF'
--filter-tcp=80 --filter-l7=http --hostlist=/opt/zapret2/ipset/zapret-hosts-youtube.txt --payload=http_req --lua-desync=fake:blob=fake_default_http:tcp_md5 --lua-desync=multisplit:pos=method+2 --new
--filter-tcp=443 --filter-l7=tls --hostlist=/opt/zapret2/ipset/zapret-hosts-youtube.txt --payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls:tcp_md5 --lua-desync=multisplit:pos=1,midsld --new
--filter-udp=443 --filter-l7=quic --hostlist=/opt/zapret2/ipset/zapret-hosts-youtube.txt --payload=quic_initial --lua-desync=fake:blob=fake_default_quic:repeats=6

--filter-tcp=443 --filter-l7=tls --hostlist=/opt/zapret2/ipset/zapret-hosts-discord.txt --payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls:tcp_md5 --lua-desync=multisplit:pos=1,midsld --new
--filter-udp=443 --filter-l7=quic --hostlist=/opt/zapret2/ipset/zapret-hosts-discord.txt --payload=quic_initial --lua-desync=fake:blob=fake_default_quic:repeats=6

--filter-tcp=80 --filter-l7=http --hostlist=/opt/zapret2/ipset/zapret-hosts.txt --payload=http_req --lua-desync=fake:blob=fake_default_http:tcp_md5 --lua-desync=multisplit:pos=method+2 --new
--filter-tcp=443 --filter-l7=tls --hostlist=/opt/zapret2/ipset/zapret-hosts.txt --payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls:tcp_md5 --lua-desync=multisplit:pos=1,midsld --new
--filter-udp=443 --filter-l7=quic --hostlist=/opt/zapret2/ipset/zapret-hosts.txt --payload=quic_initial --lua-desync=fake:blob=fake_default_quic:repeats=6

--filter-udp=3478,50000-65535 --filter-l7=stun,discord --payload=stun,discord_ip_discovery --lua-desync=fake:blob=0x00000000000000000000000000000000:repeats=2
EOF
}

pick_blob() {
	file="$1"
	fallback="$2"
	if [ -f "$file" ] && [ -s "$file" ] && dd if="$file" of=/dev/null bs=1 count=1 2>/dev/null; then
		printf "@%s" "$file"
	else
		printf "%s" "$fallback"
	fi
}

last_nonempty_line() {
	awk 'NF {last=$0} END {print last}' "$1" 2>/dev/null
}

last_nonempty_line_any() {
	file="$1"
	gz="${file}.gz"
	if [ -f "$file" ] && [ -s "$file" ]; then
		last_nonempty_line "$file"
		return
	fi
	if [ -f "$gz" ] && [ -s "$gz" ]; then
		if command -v gzip >/dev/null 2>&1; then
			gzip -cd "$gz" 2>/dev/null | awk 'NF {last=$0} END {print last}'
		elif command -v gunzip >/dev/null 2>&1; then
			gunzip -c "$gz" 2>/dev/null | awk 'NF {last=$0} END {print last}'
		elif command -v zcat >/dev/null 2>&1; then
			zcat "$gz" 2>/dev/null | awk 'NF {last=$0} END {print last}'
		fi
	fi
}

get_rkn_hostlist_path() {
	if [ -f "$INSTALL_DIR/ipset/def.sh" ]; then
		ZAPRET_BASE="$INSTALL_DIR" ZAPRET_RW="$INSTALL_DIR" . "$INSTALL_DIR/ipset/def.sh"
	fi
	echo "${ZHOSTLIST:-$INSTALL_DIR/ipset/zapret-hosts.txt}"
}

last_nonempty_line_hostlist() {
	file="$1"
	if command -v zzcat >/dev/null 2>&1; then
		zzcat "$file" 2>/dev/null | awk 'NF {last=$0} END {print last}'
	else
		last_nonempty_line_any "$file"
	fi
}

extract_blockcheck_strategy() {
	testname="$1"
	logfile="$2"
	line=$(grep -F "working strategy found" "$logfile" | grep -F "$testname" | tail -n1)
	[ -n "$line" ] || return 1
	strategy=$(echo "$line" | sed -e 's/^.*: [^ ]* //' -e 's/ !!!!!$//' -e 's/^nfqws2 //' -e 's/^dvtws2 //' -e 's/^winws2 //' | xargs)
	[ -n "$strategy" ] || return 1
	printf "%s" "$strategy"
}

extract_last_available() {
	logfile="$1"
	line=$(awk '
		/^- curl_test_/ && $0 ~ / : nfqws2 / { cur=$0 }
		/AVAIL/ && $0 !~ /UNAVAIL/ && cur!="" { res=cur }
		END { if (res!="") print res }
	' "$logfile")
	[ -n "$line" ] || return 1
	testname=$(echo "$line" | awk '{print $2}')
	strategy=$(echo "$line" | sed -e 's/^.*: nfqws2 //' | xargs)
	[ -n "$testname" ] && [ -n "$strategy" ] || return 1
	printf "%s|%s" "$testname" "$strategy"
}

run_blockcheck_background() {
	logfile="$1"
	if command -v setsid >/dev/null 2>&1; then
		BLOCKCHECK_SETSID=1
		setsid sh "$INSTALL_DIR/blockcheck2.sh" >"$logfile" 2>&1 &
	else
		BLOCKCHECK_SETSID=0
		sh "$INSTALL_DIR/blockcheck2.sh" >"$logfile" 2>&1 &
	fi
	BLOCKCHECK_PID=$!
}

stop_blockcheck() {
	pid="$1"
	if [ "$BLOCKCHECK_SETSID" = "1" ]; then
		kill -TERM -"$pid" 2>/dev/null || true
		sleep 1
		kill -KILL -"$pid" 2>/dev/null || true
	else
		if command -v pkill >/dev/null 2>&1; then
			pkill -P "$pid" 2>/dev/null || true
		fi
		if command -v killall >/dev/null 2>&1; then
			killall blockcheck2.sh 2>/dev/null || true
		fi
		kill "$pid" 2>/dev/null || true
	fi
	wait "$pid" 2>/dev/null || true
}

ensure_payload() {
	strat="$1"
	payload="$2"
	case "$strat" in
		*--payload=*) printf "%s" "$strat" ;;
		*) printf "--payload=%s %s" "$payload" "$strat" ;;
	esac
}

build_opt_from_autostrategies() {
	local yt_http yt_tls yt_quic ds_tls ds_quic rkn_http rkn_tls rkn_quic
	local def_http def_tls def_quic

	def_http="--payload=http_req --lua-desync=fake:blob=fake_default_http:tcp_md5 --lua-desync=multisplit:pos=method+2"
	def_tls="--payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls:tcp_md5 --lua-desync=multisplit:pos=1,midsld"
	def_quic="--payload=quic_initial --lua-desync=fake:blob=fake_default_quic:repeats=6"

	yt_http=$(get_kv Z24K_YT_HTTP_STRAT)
	yt_tls=$(get_kv Z24K_YT_TLS_STRAT)
	yt_quic=$(get_kv Z24K_YT_QUIC_STRAT)
	ds_tls=$(get_kv Z24K_DS_TLS_STRAT)
	ds_quic=$(get_kv Z24K_DS_QUIC_STRAT)
	rkn_http=$(get_kv Z24K_RKN_HTTP_STRAT)
	rkn_tls=$(get_kv Z24K_RKN_TLS_STRAT)
	rkn_quic=$(get_kv Z24K_RKN_QUIC_STRAT)

	yt_http=$(ensure_payload "${yt_http:-$def_http}" "http_req")
	yt_tls=$(ensure_payload "${yt_tls:-$def_tls}" "tls_client_hello")
	yt_quic=$(ensure_payload "${yt_quic:-$def_quic}" "quic_initial")
	ds_tls=$(ensure_payload "${ds_tls:-$def_tls}" "tls_client_hello")
	ds_quic=$(ensure_payload "${ds_quic:-$def_quic}" "quic_initial")
	rkn_http=$(ensure_payload "${rkn_http:-$def_http}" "http_req")
	rkn_tls=$(ensure_payload "${rkn_tls:-$def_tls}" "tls_client_hello")
	rkn_quic=$(ensure_payload "${rkn_quic:-$def_quic}" "quic_initial")

	cat <<EOF
--filter-tcp=80 --filter-l7=http --hostlist=/opt/zapret2/ipset/zapret-hosts-youtube.txt $yt_http --new
--filter-tcp=443 --filter-l7=tls --hostlist=/opt/zapret2/ipset/zapret-hosts-youtube.txt $yt_tls --new
--filter-udp=443 --filter-l7=quic --hostlist=/opt/zapret2/ipset/zapret-hosts-youtube.txt $yt_quic

--filter-tcp=443 --filter-l7=tls --hostlist=/opt/zapret2/ipset/zapret-hosts-discord.txt $ds_tls --new
--filter-udp=443 --filter-l7=quic --hostlist=/opt/zapret2/ipset/zapret-hosts-discord.txt $ds_quic

--filter-tcp=80 --filter-l7=http --hostlist=/opt/zapret2/ipset/zapret-hosts.txt $rkn_http --new
--filter-tcp=443 --filter-l7=tls --hostlist=/opt/zapret2/ipset/zapret-hosts.txt $rkn_tls --new
--filter-udp=443 --filter-l7=quic --hostlist=/opt/zapret2/ipset/zapret-hosts.txt $rkn_quic

--filter-udp=3478,50000-65535 --filter-l7=stun,discord --payload=stun,discord_ip_discovery --lua-desync=fake:blob=0x00000000000000000000000000000000:repeats=2
EOF
}

build_opt_with_override() {
	list_key="$1"
	ov_tls="$2"
	ov_quic="$3"

	yt_http=$(get_kv Z24K_YT_HTTP_STRAT)
	yt_tls=$(get_kv Z24K_YT_TLS_STRAT)
	yt_quic=$(get_kv Z24K_YT_QUIC_STRAT)
	ds_tls=$(get_kv Z24K_DS_TLS_STRAT)
	ds_quic=$(get_kv Z24K_DS_QUIC_STRAT)
	rkn_http=$(get_kv Z24K_RKN_HTTP_STRAT)
	rkn_tls=$(get_kv Z24K_RKN_TLS_STRAT)
	rkn_quic=$(get_kv Z24K_RKN_QUIC_STRAT)

	if [ -n "$ov_tls" ] || [ -n "$ov_quic" ]; then
		case "$list_key" in
			yt)
				[ -n "$ov_tls" ] && yt_tls="$ov_tls"
				[ -n "$ov_quic" ] && yt_quic="$ov_quic"
				;;
			ds)
				[ -n "$ov_tls" ] && ds_tls="$ov_tls"
				[ -n "$ov_quic" ] && ds_quic="$ov_quic"
				;;
			rkn)
				[ -n "$ov_tls" ] && rkn_tls="$ov_tls"
				[ -n "$ov_quic" ] && rkn_quic="$ov_quic"
				;;
		esac
	fi

	def_http="--payload=http_req --lua-desync=fake:blob=fake_default_http:tcp_md5 --lua-desync=multisplit:pos=method+2"
	def_tls="--payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls:tcp_md5 --lua-desync=multisplit:pos=1,midsld"
	def_quic="--payload=quic_initial --lua-desync=fake:blob=fake_default_quic:repeats=6"

	yt_http=$(ensure_payload "${yt_http:-$def_http}" "http_req")
	yt_tls=$(ensure_payload "${yt_tls:-$def_tls}" "tls_client_hello")
	yt_quic=$(ensure_payload "${yt_quic:-$def_quic}" "quic_initial")
	ds_tls=$(ensure_payload "${ds_tls:-$def_tls}" "tls_client_hello")
	ds_quic=$(ensure_payload "${ds_quic:-$def_quic}" "quic_initial")
	rkn_http=$(ensure_payload "${rkn_http:-$def_http}" "http_req")
	rkn_tls=$(ensure_payload "${rkn_tls:-$def_tls}" "tls_client_hello")
	rkn_quic=$(ensure_payload "${rkn_quic:-$def_quic}" "quic_initial")

	cat <<EOF
--filter-tcp=80 --filter-l7=http --hostlist=/opt/zapret2/ipset/zapret-hosts-youtube.txt $yt_http --new
--filter-tcp=443 --filter-l7=tls --hostlist=/opt/zapret2/ipset/zapret-hosts-youtube.txt $yt_tls --new
--filter-udp=443 --filter-l7=quic --hostlist=/opt/zapret2/ipset/zapret-hosts-youtube.txt $yt_quic

--filter-tcp=443 --filter-l7=tls --hostlist=/opt/zapret2/ipset/zapret-hosts-discord.txt $ds_tls --new
--filter-udp=443 --filter-l7=quic --hostlist=/opt/zapret2/ipset/zapret-hosts-discord.txt $ds_quic

--filter-tcp=80 --filter-l7=http --hostlist=/opt/zapret2/ipset/zapret-hosts.txt $rkn_http --new
--filter-tcp=443 --filter-l7=tls --hostlist=/opt/zapret2/ipset/zapret-hosts.txt $rkn_tls --new
--filter-udp=443 --filter-l7=quic --hostlist=/opt/zapret2/ipset/zapret-hosts.txt $rkn_quic

--filter-udp=3478,50000-65535 --filter-l7=stun,discord --payload=stun,discord_ip_discovery --lua-desync=fake:blob=0x00000000000000000000000000000000:repeats=2
EOF
}

preset_manual_blobs() {
	local http_blob tls_yt_blob quic_yt_blob tls_generic_blob quic_generic_blob discord_blob
	http_blob=$(pick_blob "$INSTALL_DIR/files/fake/http_iana_org.bin" "fake_default_http")
	tls_yt_blob=$(pick_blob "$INSTALL_DIR/files/fake/tls_clienthello_www_google_com.bin" "fake_default_tls")
	quic_yt_blob=$(pick_blob "$INSTALL_DIR/files/fake/quic_initial_rr2---sn-gvnuxaxjvh-o8ge_googlevideo_com.bin" "fake_default_quic")
	tls_generic_blob=$(pick_blob "$INSTALL_DIR/files/fake/tls_clienthello_iana_org.bin" "fake_default_tls")
	quic_generic_blob=$(pick_blob "$INSTALL_DIR/files/fake/quic_initial_www_google_com.bin" "fake_default_quic")
	discord_blob=$(pick_blob "$INSTALL_DIR/files/fake/discord-ip-discovery-without-port.bin" "0x00000000000000000000000000000000")

	cat <<EOF
--filter-tcp=80 --filter-l7=http --hostlist=/opt/zapret2/ipset/zapret-hosts-youtube.txt --payload=http_req --lua-desync=fake:blob=$http_blob:tcp_md5 --lua-desync=multisplit:pos=method+2 --new
--filter-tcp=443 --filter-l7=tls --hostlist=/opt/zapret2/ipset/zapret-hosts-youtube.txt --payload=tls_client_hello --lua-desync=fake:blob=$tls_yt_blob:tcp_md5 --lua-desync=multisplit:pos=1,midsld --new
--filter-udp=443 --filter-l7=quic --hostlist=/opt/zapret2/ipset/zapret-hosts-youtube.txt --payload=quic_initial --lua-desync=fake:blob=$quic_yt_blob:repeats=6

--filter-tcp=443 --filter-l7=tls --hostlist=/opt/zapret2/ipset/zapret-hosts-discord.txt --payload=tls_client_hello --lua-desync=fake:blob=$tls_generic_blob:tcp_md5 --lua-desync=multisplit:pos=1,midsld --new
--filter-udp=443 --filter-l7=quic --hostlist=/opt/zapret2/ipset/zapret-hosts-discord.txt --payload=quic_initial --lua-desync=fake:blob=$quic_generic_blob:repeats=6

--filter-tcp=80 --filter-l7=http --hostlist=/opt/zapret2/ipset/zapret-hosts.txt --payload=http_req --lua-desync=fake:blob=$http_blob:tcp_md5 --lua-desync=multisplit:pos=method+2 --new
--filter-tcp=443 --filter-l7=tls --hostlist=/opt/zapret2/ipset/zapret-hosts.txt --payload=tls_client_hello --lua-desync=fake:blob=$tls_generic_blob:tcp_md5 --lua-desync=multisplit:pos=1,midsld --new
--filter-udp=443 --filter-l7=quic --hostlist=/opt/zapret2/ipset/zapret-hosts.txt --payload=quic_initial --lua-desync=fake:blob=$quic_generic_blob:repeats=6

--filter-udp=3478,50000-65535 --filter-l7=stun,discord --payload=stun,discord_ip_discovery --lua-desync=fake:blob=$discord_blob:repeats=2
EOF
}

preset_magisk() {
	build_opt_from_magisk_blocks
}

preset_categories() {
	ensure_category_files
	sync_category_lists
	build_opt_from_categories
}

preset_aggressive() {
	cat <<'EOF'
--filter-tcp=80 --filter-l7=http <HOSTLIST> --payload=http_req --lua-desync=fake:blob=fake_default_http:tcp_md5:ip_autottl=-2,3-20 --lua-desync=fakedsplit:ip_autottl=-2,3-20:tcp_md5 --new
--filter-tcp=443 --filter-l7=tls <HOSTLIST> --payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls:tcp_md5:repeats=11:tls_mod=rnd,dupsid,padencap --lua-desync=multidisorder:pos=midsld --new
--filter-udp=443 --filter-l7=quic <HOSTLIST_NOAUTO> --payload=quic_initial --lua-desync=fake:blob=fake_default_quic:repeats=11
EOF
}

preset_universal() {
	build_opt_from_blocks
}
preset_minimal() {
	cat <<'EOF'
--filter-tcp=80 --filter-l7=http <HOSTLIST> --payload=http_req --lua-desync=fake:blob=fake_default_http:tcp_md5 --lua-desync=multisplit:pos=method+2 --new
--filter-tcp=443 --filter-l7=tls <HOSTLIST> --payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls:tcp_md5:tcp_seq=-10000 --lua-desync=multidisorder:pos=1,midsld
EOF
}

apply_preset_quiet() {
	name="$1"
	opt="$2"
	ensure_split_hostlists
	set_opt_block "$opt"
	set_kv NFQWS2_ENABLE 1
	set_kv Z24K_PRESET "$name"
	restart_service_quiet
}

restart_service_quiet() {
	if [ -x "$SERVICE" ]; then
		"$SERVICE" restart >/dev/null 2>&1
	fi
}

apply_preset() {
	name="$1"
	opt="$2"
	echo -e "${cyan}Применение стратегии: ${green}${name}${plain}"
	ensure_split_hostlists
	set_opt_block "$opt"
	set_kv NFQWS2_ENABLE 1
	set_kv Z24K_PRESET "$name"
	restart_service
	echo -e "${green}Готово.${plain}"
	pause_enter
}

ensure_split_hostlists() {
	mkdir -p "$INSTALL_DIR/ipset"
	[ -f "$INSTALL_DIR/ipset/zapret-hosts-user.txt" ] || : > "$INSTALL_DIR/ipset/zapret-hosts-user.txt"
	[ -f "$INSTALL_DIR/ipset/zapret-hosts-youtube.txt" ] || : > "$INSTALL_DIR/ipset/zapret-hosts-youtube.txt"
	[ -f "$INSTALL_DIR/ipset/zapret-hosts-discord.txt" ] || : > "$INSTALL_DIR/ipset/zapret-hosts-discord.txt"
	[ -f "$INSTALL_DIR/ipset/zapret-hosts.txt" ] || : > "$INSTALL_DIR/ipset/zapret-hosts.txt"
}

test_url() {
	url="$1"
	code=$(curl -k --max-time 8 --connect-timeout 5 -s -o /dev/null -w "%{http_code}" "$url")
	rc=$?
	if [ "$rc" -ne 0 ] || [ "$code" = "000" ]; then
		printf "%-50s %s\n" "$url" "FAIL"
		return 1
	elif [ "$code" -ge 200 ] && [ "$code" -lt 400 ]; then
		printf "%-50s %s\n" "$url" "OK ($code)"
		return 0
	else
		printf "%-50s %s\n" "$url" "WARN ($code)"
		return 1
	fi
}

run_blockcheck() {
	if [ -x "$INSTALL_DIR/blockcheck2.sh" ]; then
		ZAPRET_BASE="$INSTALL_DIR" ZAPRET_RW="$INSTALL_DIR" sh "$INSTALL_DIR/blockcheck2.sh"
	else
		echo -e "${yellow}blockcheck2.sh not found in $INSTALL_DIR.${plain}"
	fi
	pause_enter
}

auto_pick_strategy() {
	list_key="$1"
	list_file="$2"
	label="$3"
	url="$4"
	domain=""
	tmpdir=$(pick_tmpdir)
	mkdir -p "$tmpdir"
	logfile="$tmpdir/z24k-blockcheck-${list_key}.log"

	ensure_split_hostlists
	if [ "$list_key" = "rkn" ]; then
		list_file=$(get_rkn_hostlist_path)
		if [ -z "$(last_nonempty_line_hostlist "$list_file")" ]; then
			ensure_rkn_bootstrap_hosts
			update_rkn_list || true
		fi
		domain="rutracker.org"
	else
		domain=$(last_nonempty_line_any "$list_file")
		if [ -z "$domain" ]; then
			echo -e "${yellow}Список пустой: $list_file${plain}"
			pause_enter
			return
		fi
	fi

	if [ -x "$SERVICE" ]; then
		"$SERVICE" stop || true
	fi

	echo -e "${cyan}Подбор стратегии для ${green}${label}${plain} (${domain})"
	log "Лог blockcheck2: $logfile"
	: > "$logfile"
	scanlevel=""
	while :; do
		ZAPRET_BASE="$INSTALL_DIR"
		ZAPRET_RW="$INSTALL_DIR"
		BATCH=1
		TEST=standard
		DOMAINS="$domain"
		IPVS=4
		SCANLEVEL="$scanlevel"
		ENABLE_HTTP=0
		ENABLE_HTTPS_TLS12=1
		ENABLE_HTTPS_TLS13=1
		ENABLE_HTTP3=1
		export ENABLE_HTTP ENABLE_HTTPS_TLS12 ENABLE_HTTPS_TLS13 ENABLE_HTTP3
		run_blockcheck_background "$logfile"
		pid=$BLOCKCHECK_PID
		echo -n "Идет подбор"
		found_tls=""
		found_quic=""
		last_entry=""
		while kill -0 "$pid" 2>/dev/null; do
			printf "."
			entry=$(extract_last_available "$logfile" || true)
			if [ -n "$entry" ]; then
				[ "$entry" = "$last_entry" ] && { sleep 2; continue; }
				last_entry="$entry"
				testname=${entry%%|*}
				strategy=${entry#*|}
				case "$testname" in
					curl_test_https_tls13|curl_test_https_tls12)
						found_tls="$strategy"
						;;
					curl_test_http3)
						found_quic="$strategy"
						;;
					*)
						;;
				esac
				if [ -n "$found_tls" ] || [ -n "$found_quic" ]; then
					stop_blockcheck "$pid"
					break
				fi
			fi
			sleep 2
		done
		echo ""
		wait "$pid" 2>/dev/null || true

		if [ -n "$found_tls" ] || [ -n "$found_quic" ]; then
			save_config_snapshot
			tmp_opt=$(build_opt_with_override "$list_key" "$found_tls" "$found_quic")
			set_opt_block "$tmp_opt"
			set_kv NFQWS2_ENABLE 1
			restart_service
			test_url="$domain"
			case "$test_url" in
				http://*|https://*) ;;
				*) test_url="https://$test_url/" ;;
				esac
			if ! test_tcp_suite "$test_url"; then
				echo -e "${yellow}ТСП проверка не прошла, продолжаю поиск.${plain}"
				restore_config_snapshot
				restart_service
				: > "$logfile"
				continue
			fi
			echo -e "${green}Стратегия применена временно. Проверьте доступность.${plain}"
			read_tty "Сохранить (s), продолжить (c) или выйти (q)? " choice
			case "$choice" in
				s|S)
					[ -n "$found_tls" ] && tls_strat="$found_tls"
					[ -n "$found_quic" ] && quic_strat="$found_quic"
					break
					;;
				c|C)
					restore_config_snapshot
					restart_service
					: > "$logfile"
					continue
					;;
				*)
					restore_config_snapshot
					restart_service
					return
					;;
			esac
		else
			break
		fi
	done
	unset ENABLE_HTTP ENABLE_HTTPS_TLS12 ENABLE_HTTPS_TLS13 ENABLE_HTTP3

	if [ -z "$tls_strat" ] && [ -z "$quic_strat" ]; then
		tls13_strat=$(extract_blockcheck_strategy "curl_test_https_tls13" "$logfile" || true)
		tls12_strat=$(extract_blockcheck_strategy "curl_test_https_tls12" "$logfile" || true)
		quic_strat=$(extract_blockcheck_strategy "curl_test_http3" "$logfile" || true)

		tls_strat="$tls13_strat"
		[ -z "$tls_strat" ] && tls_strat="$tls12_strat"
	fi

	if [ -z "$tls_strat" ] && [ -z "$quic_strat" ]; then
		echo -e "${yellow}Стратегия не найдена. Лог: $logfile${plain}"
		pause_enter
		return
	fi

	case "$list_key" in
		yt)
			[ -n "$http_strat" ] && set_kv Z24K_YT_HTTP_STRAT "$http_strat"
			[ -n "$tls_strat" ] && set_kv Z24K_YT_TLS_STRAT "$tls_strat"
			[ -n "$quic_strat" ] && set_kv Z24K_YT_QUIC_STRAT "$quic_strat"
			;;
		ds)
			[ -n "$tls_strat" ] && set_kv Z24K_DS_TLS_STRAT "$tls_strat"
			[ -n "$quic_strat" ] && set_kv Z24K_DS_QUIC_STRAT "$quic_strat"
			;;
		rkn)
			[ -n "$http_strat" ] && set_kv Z24K_RKN_HTTP_STRAT "$http_strat"
			[ -n "$tls_strat" ] && set_kv Z24K_RKN_TLS_STRAT "$tls_strat"
			[ -n "$quic_strat" ] && set_kv Z24K_RKN_QUIC_STRAT "$quic_strat"
			;;
	esac

	opt=$(build_opt_from_autostrategies)
	set_opt_block "$opt"
	set_kv NFQWS2_ENABLE 1
	set_kv Z24K_PRESET auto
	restart_service

	echo -e "${green}Стратегия применена для $label.${plain}"
	pause_enter
}

test_strategies() {
	if ! need_cmd curl; then
		echo "curl is required for tests."
		pause_enter
		return
	fi
	if [ -f "$CONFIG" ]; then
		mkdir -p "$TMP_DIR"
		cp -f "$CONFIG" "$TMP_DIR/config.test.bak"
	fi
	set_mode_hostlist
	ensure_hostlist_file
	log "Preparing hostlist"
	update_user_lists >/dev/null 2>&1 || true
	urls="https://www.youtube.com/ https://discord.com/ https://discord.gg/ https://antizapret.prostovpn.org:8443/domains-export.txt https://antizapret.prostovpn.org/domains-export.txt"
	for name in categories; do
		ok=0
		total=0
		echo -e "${cyan}Testing: ${green}${name}${plain}"
		case "$name" in
			categories) apply_preset_quiet "$name" "$(preset_categories)" ;;
		esac
		for url in $urls; do
			total=$((total + 1))
			out=$(test_url "$url")
			rc=$?
			echo "$out"
			[ "$rc" -eq 0 ] && ok=$((ok + 1))
		done
		echo -e "${green}Result:${plain} ${ok}/${total} OK"
		echo ""
	done
	if [ -f "$TMP_DIR/config.test.bak" ]; then
		cp -f "$TMP_DIR/config.test.bak" "$CONFIG"
		restart_service_quiet
	fi
	pause_enter
}

default_block_youtube() {
	cat <<'EOF'
--filter-tcp=80 --filter-l7=http --hostlist=/opt/zapret2/ipset/zapret-hosts-youtube.txt --payload=http_req --lua-desync=fake:blob=fake_default_http:ip_autottl=-2,3-20:ip6_autottl=-2,3-20:tcp_md5 --lua-desync=fakedsplit:ip_autottl=-2,3-20:ip6_autottl=-2,3-20:tcp_md5 --new
--filter-tcp=443 --filter-l7=tls --hostlist=/opt/zapret2/ipset/zapret-hosts-youtube.txt --payload=tls_client_hello --lua-desync=multisplit:pos=10:seqovl=1 --new
--filter-udp=443 --filter-l7=quic --hostlist=/opt/zapret2/ipset/zapret-hosts-youtube.txt --payload=quic_initial --lua-desync=fake:blob=fake_default_quic:repeats=11
EOF
}

default_block_discord() {
	cat <<'EOF'
--filter-tcp=443 --filter-l7=tls --hostlist=/opt/zapret2/ipset/zapret-hosts-discord.txt --payload=tls_client_hello --lua-desync=tcpseg:pos=0,1:ip_id=rnd:repeats=1 --lua-desync=multidisorder:pos=midsld --new
--filter-udp=443 --filter-l7=quic --hostlist=/opt/zapret2/ipset/zapret-hosts-discord.txt --payload=quic_initial --lua-desync=fake:blob=fake_default_quic:repeats=11
EOF
}

default_block_rkn() {
	cat <<'EOF'
--filter-tcp=80 --filter-l7=http --hostlist=/opt/zapret2/ipset/zapret-hosts.txt --payload=http_req --lua-desync=fake:blob=fake_default_http:tcp_md5:ip_autottl=-2,3-20 --lua-desync=fakedsplit:ip_autottl=-2,3-20:tcp_md5 --new
--filter-tcp=443 --filter-l7=tls --hostlist=/opt/zapret2/ipset/zapret-hosts.txt --payload=tls_client_hello --lua-desync=tcpseg:pos=0,1:ip_id=rnd:repeats=1 --lua-desync=multidisorder:pos=midsld --new
--filter-udp=443 --filter-l7=quic --hostlist=/opt/zapret2/ipset/zapret-hosts.txt --payload=quic_initial --lua-desync=fake:blob=fake_default_quic:repeats=11
EOF
}

default_block_discord_voice() {
	cat <<'EOF'
--filter-udp=3478,50000-65535 --filter-l7=stun,discord --payload=stun,discord_ip_discovery --lua-desync=fake:blob=0x00000000000000000000000000000000:repeats=2
EOF
}

magisk_block_youtube() {
	local tls_blob quic_blob seqovl_opts
	tls_blob=$(pick_blob "$INSTALL_DIR/files/fake/tls_clienthello_www_google_com.bin" "fake_default_tls")
	quic_blob=$(pick_blob "$INSTALL_DIR/files/fake/quic_initial_www_google_com.bin" "fake_default_quic")
	seqovl_opts=$(magisk_seqovl_opts)
	cat <<EOF
--filter-tcp=443 --filter-l7=tls --hostlist=/opt/zapret2/ipset/zapret-hosts-youtube.txt --payload=tls_client_hello --lua-desync=send:repeats=2 --lua-desync=syndata:blob=$tls_blob $seqovl_opts --new
--filter-udp=443 --filter-l7=quic --hostlist=/opt/zapret2/ipset/zapret-hosts-youtube.txt --payload=quic_initial --lua-desync=fake:blob=$quic_blob:repeats=6
EOF
}

magisk_block_discord() {
	local tls_blob seqovl_opts
	tls_blob=$(pick_blob "$INSTALL_DIR/files/fake/tls_clienthello_www_google_com.bin" "fake_default_tls")
	seqovl_opts=$(magisk_seqovl_opts)
	cat <<EOF
--filter-tcp=443 --filter-l7=tls --hostlist=/opt/zapret2/ipset/zapret-hosts-discord.txt --payload=tls_client_hello --lua-desync=send:repeats=2 --lua-desync=syndata:blob=$tls_blob $seqovl_opts --new
EOF
}

magisk_block_rkn() {
	local http_blob tls_blob quic_blob seqovl_opts
	http_blob=$(pick_blob "$INSTALL_DIR/files/fake/http_iana_org.bin" "fake_default_http")
	tls_blob=$(pick_blob "$INSTALL_DIR/files/fake/tls_clienthello_www_google_com.bin" "fake_default_tls")
	quic_blob=$(pick_blob "$INSTALL_DIR/files/fake/quic_initial_www_google_com.bin" "fake_default_quic")
	seqovl_opts=$(magisk_seqovl_opts)
	cat <<EOF
--filter-tcp=80 --filter-l7=http --hostlist=/opt/zapret2/ipset/zapret-hosts.txt --payload=http_req --lua-desync=fake:blob=$http_blob:tcp_md5 --lua-desync=multisplit:pos=method+2 --new
--filter-tcp=443 --filter-l7=tls --hostlist=/opt/zapret2/ipset/zapret-hosts.txt --payload=tls_client_hello --lua-desync=send:repeats=2 --lua-desync=syndata:blob=$tls_blob $seqovl_opts --new
--filter-udp=443 --filter-l7=quic --hostlist=/opt/zapret2/ipset/zapret-hosts.txt --payload=quic_initial --lua-desync=fake:blob=$quic_blob:repeats=6
EOF
}

magisk_seqovl_opts() {
	local file
	file="$INSTALL_DIR/files/fake/tls_clienthello_www_google_com.bin"
	if [ -f "$file" ] && [ -s "$file" ]; then
		printf "%s" "--lua-desync=multisplit:seqovl=700:seqovl_pattern=tls_google:tcp_flags_unset=ack"
	else
		printf "%s" "--lua-desync=multisplit:seqovl=700:tcp_flags_unset=ack"
	fi
}

magisk_block_discord_voice() {
	cat <<'EOF'
--filter-udp=3478,50000-65535 --filter-l7=stun,discord --payload=stun,discord_ip_discovery --out-range=-n10 --lua-desync=fake:blob=0x00000000000000000000000000000000:repeats=2
EOF
}

build_opt_from_magisk_blocks() {
	local prefix
	prefix=$(magisk_blob_prefix)
	yblock=$(magisk_block_youtube)
	dblock=$(magisk_block_discord)
	rblock=$(magisk_block_rkn)
	vblock=$(magisk_block_discord_voice)
	printf "%s\n%s\n%s\n%s\n%s\n" "$prefix" "$yblock" "$dblock" "$rblock" "$vblock"
}

magisk_blob_prefix() {
	local file
	file="$INSTALL_DIR/files/fake/tls_clienthello_www_google_com.bin"
	if [ -f "$file" ] && [ -s "$file" ]; then
		printf "%s" "--blob=tls_google:@$file"
	fi
}

build_opt_from_blocks() {
	yblock=$(default_block_youtube)
	dblock=$(default_block_discord)
	rblock=$(default_block_rkn)
	vblock=$(default_block_discord_voice)
	printf "%s\n%s\n%s\n%s\n" "$yblock" "$dblock" "$rblock" "$vblock"
}

toggle_nfqws2() {
	cur=$(get_kv NFQWS2_ENABLE)
	if [ "$cur" = "1" ]; then
		set_kv NFQWS2_ENABLE 0
		echo -e "${yellow}NFQWS2 отключен.${plain}"
	else
		set_kv NFQWS2_ENABLE 1
		echo -e "${green}NFQWS2 включен.${plain}"
	fi
	restart_service
	pause_enter
}

do_uninstall() {
	echo -e "${yellow}Удаление zapret2 и сервисов...${plain}"
	if [ -x "$SERVICE" ]; then
		"$SERVICE" stop || true
	fi
	rm -f /opt/etc/init.d/S90-zapret2
	rm -f /opt/etc/ndm/netfilter.d/000-zapret2.sh
	rm -f /opt/etc/init.d/S00fix
	rm -f /opt/bin/z24k
	rm -rf "$INSTALL_DIR"
	echo -e "${green}Удаление завершено.${plain}"
	pause_enter
}

update_user_lists() {
	local tmp
	tmp="$TMP_DIR/z24k-hosts.txt"
	mkdir -p "$TMP_DIR" "$INSTALL_DIR/ipset"

	log "Updating user lists"
	: > "$tmp"
	if ! fetch "$LISTS_RAW/youtube.txt" "$TMP_DIR/youtube.txt"; then
		cat <<'EOF' > "$TMP_DIR/youtube.txt"
youtube.com
youtu.be
ytimg.com
googleusercontent.com
googlevideo.com
EOF
	fi
	if ! fetch "$LISTS_RAW/discord.txt" "$TMP_DIR/discord.txt"; then
		cat <<'EOF' > "$TMP_DIR/discord.txt"
discord.com
discord.gg
discordapp.com
discordapp.net
discordcdn.com
EOF
	fi
	if ! fetch "$LISTS_RAW/rkn-download.txt" "$TMP_DIR/rkn-download.txt"; then
		cat <<'EOF' > "$TMP_DIR/rkn-download.txt"
antizapret.prostovpn.org
prostovpn.org
EOF
	fi

	cp -f "$TMP_DIR/youtube.txt" "$INSTALL_DIR/ipset/zapret-hosts-youtube.txt"
	cp -f "$TMP_DIR/discord.txt" "$INSTALL_DIR/ipset/zapret-hosts-discord.txt"

	cat "$TMP_DIR/youtube.txt" "$TMP_DIR/discord.txt" "$TMP_DIR/rkn-download.txt" | awk 'NF {print $0}' | sort -u > "$tmp"
	cp -f "$tmp" "$INSTALL_DIR/ipset/zapret-hosts-user.txt"
}

ensure_hostlist_file() {
	mkdir -p "$INSTALL_DIR/ipset"
	: > "$INSTALL_DIR/ipset/zapret-hosts-user.txt"
}

ensure_extra_blobs() {
	local base dst file
	base="$Z24K_RAW/files/fake"
	dst="$INSTALL_DIR/files/fake"
	mkdir -p "$dst"
	for file in tls_clienthello_www_google_com.bin http_iana_org.bin quic_initial_www_google_com.bin; do
		if [ ! -s "$dst/$file" ]; then
			fetch "$base/$file" "$dst/$file" || true
		fi
	done
}

ensure_category_files() {
	mkdir -p "$INSTALL_DIR"
	[ "${Z24K_CAT_READY:-0}" -eq 1 ] && return 0
	log "Downloading categories/strategies/blobs"
	fetch "$CAT_RAW" "$CATEGORIES_FILE" || true
	fetch "$TCP_RAW" "$STRAT_TCP_FILE" || true
	fetch "$UDP_RAW" "$STRAT_UDP_FILE" || true
	fetch "$STUN_RAW" "$STRAT_STUN_FILE" || true
	fetch "$BLOBS_RAW" "$BLOBS_FILE" || true
	Z24K_CAT_READY=1
}

ensure_blob_files() {
	local line file
	[ -f "$BLOBS_FILE" ] || return 0
	mkdir -p "$INSTALL_DIR/files/fake"
	while IFS= read -r line || [ -n "$line" ]; do
		line=$(printf "%s" "$line" | tr -d '\r')
		case "$line" in
			""|\#*|";"*) continue ;;
			--blob=*)
				file=${line##*@bin/}
				[ -z "$file" ] && continue
				if [ ! -s "$INSTALL_DIR/files/fake/$file" ]; then
					log "Downloading blob: $file"
					fetch "$Z24K_RAW/files/fake/$file" "$INSTALL_DIR/files/fake/$file" || true
				fi
				;;
		esac
	done < "$BLOBS_FILE"
}

sync_all_lists() {
	local tmp file
	mkdir -p "$LISTS_DIR" "$TMP_DIR"
	tmp="$TMP_DIR/z24k-lists-index.txt"
	fetch "$LISTS_RAW/index.txt?nocache=$(date +%s)" "$tmp" || return 0
	while IFS= read -r file || [ -n "$file" ]; do
		file=$(printf "%s" "$file" | tr -d '\r')
		[ -z "$file" ] && continue
		if [ -s "$LISTS_DIR/$file" ]; then
			continue
		fi
		log "Downloading list: $file"
		fetch "$LISTS_RAW/$file?nocache=$(date +%s)" "$LISTS_DIR/$file" || true
	done < "$tmp"
}

sync_category_lists() {
	local line key value tmp current hostlist ipset strategy
	mkdir -p "$LISTS_DIR" "$TMP_DIR"
	tmp="$TMP_DIR/z24k-category-lists.txt"
	: > "$tmp"
	while IFS= read -r line || [ -n "$line" ]; do
		line=$(printf "%s" "$line" | tr -d '\r')
		case "$line" in
			""|\#*|";"*) continue ;;
		esac
		if echo "$line" | grep -q '^\[.*\]$'; then
			if [ -n "$current" ] && [ -n "$strategy" ] && [ "$strategy" != "disabled" ]; then
				[ -n "$hostlist" ] && printf "%s\n" "$hostlist" >> "$tmp"
				[ -n "$ipset" ] && printf "%s\n" "$ipset" >> "$tmp"
			fi
			current=${line#\[}
			current=${current%\]}
			hostlist=""
			ipset=""
			strategy=""
			continue
		fi
		if echo "$line" | grep -q '^[a-z_]*='; then
			key=$(printf "%s" "$line" | cut -d'=' -f1)
			value=$(printf "%s" "$line" | cut -d'=' -f2-)
			case "$key" in
				hostlist) hostlist="$value" ;;
				ipset) ipset="$value" ;;
				strategy) strategy="$value" ;;
			esac
		fi
	done < "$CATEGORIES_FILE"
	if [ -n "$current" ] && [ -n "$strategy" ] && [ "$strategy" != "disabled" ]; then
		[ -n "$hostlist" ] && printf "%s\n" "$hostlist" >> "$tmp"
		[ -n "$ipset" ] && printf "%s\n" "$ipset" >> "$tmp"
	fi
	sort -u "$tmp" | while IFS= read -r file; do
		[ -z "$file" ] && continue
		if [ -s "$LISTS_DIR/$file" ]; then
			continue
		fi
		log "Downloading list: $file"
		fetch "$LISTS_RAW/$file?nocache=$(date +%s)" "$LISTS_DIR/$file" || true
	done
}

build_blob_prefix_from_file() {
	local line prefix out
	[ -f "$1" ] || return 0
	prefix=""
	while IFS= read -r line || [ -n "$line" ]; do
		line=$(printf "%s" "$line" | tr -d '\r')
		case "$line" in
			""|\#*|";"*) continue ;;
			--blob=*)
				out=${line//@bin\//@$INSTALL_DIR/files/fake/}
				if [ -n "$prefix" ]; then
					prefix="$prefix $out"
				else
					prefix="$out"
				fi
				;;
		esac
	done < "$1"
	printf "%s" "$prefix"
}

get_strategy_args_from_ini() {
	local file name
	file="$1"
	name="$2"
	[ -f "$file" ] || return 0
	in_section=0
	while IFS= read -r line || [ -n "$line" ]; do
		line=$(printf "%s" "$line" | tr -d '\r')
		if [ "$line" = "[$name]" ]; then
			in_section=1
			continue
		fi
		case "$line" in
			"["*"]") [ "$in_section" -eq 1 ] && break ;;
		esac
		if [ "$in_section" -eq 1 ] && [ "${line%%=*}" = "args" ]; then
			printf "%s\n" "${line#*=}"
			return 0
		fi
	done < "$file"
}

build_category_filter() {
	local mode file
	mode="$1"
	file="$2"
	case "$mode" in
		hostlist) [ -n "$file" ] && printf "%s" "--hostlist=$LISTS_DIR/$file" ;;
		ipset) [ -n "$file" ] && printf "%s" "--ipset=$LISTS_DIR/$file" ;;
	esac
}

build_category_opts() {
	local proto mode file strategy filter_opts args full
	proto="$1"
	mode="$2"
	file="$3"
	strategy="$4"
	filter_opts=$(build_category_filter "$mode" "$file")
	case "$proto" in
		stun)
			args=$(get_strategy_args_from_ini "$STRAT_STUN_FILE" "$strategy")
			[ -z "$args" ] && return 1
			full="$args"
			[ -n "$filter_opts" ] && full="$filter_opts $args"
			printf "%s" "$full"
			;;
		udp)
			args=$(get_strategy_args_from_ini "$STRAT_UDP_FILE" "$strategy")
			[ -z "$args" ] && return 1
			full="--out-range=-n$PKT_OUT --filter-udp=443,1400,50000-51000"
			[ -n "$filter_opts" ] && full="$full $filter_opts"
			printf "%s %s" "$full" "$args"
			;;
		tcp|*)
			args=$(get_strategy_args_from_ini "$STRAT_TCP_FILE" "$strategy")
			[ -z "$args" ] && return 1
			full="--out-range=-n$PKT_OUT --filter-tcp=80,443"
			[ -n "$filter_opts" ] && full="$full $filter_opts"
			printf "%s %s" "$full" "$args"
			;;
	esac
}

build_opt_from_categories() {
	local line current protocol hostlist ipset filter_mode strategy opts prefix first effective_mode filter_file cat_opts key value
	ensure_category_files
	ensure_blob_files
	[ -f "$CATEGORIES_FILE" ] || return 0
	prefix=$(build_blob_prefix_from_file "$BLOBS_FILE")
	opts=""
	[ -n "$prefix" ] && opts="$prefix"
	first=1
	current=""
	protocol="tcp"
	hostlist=""
	ipset=""
	filter_mode=""
	strategy=""
	while IFS= read -r line || [ -n "$line" ]; do
		line=$(printf "%s" "$line" | tr -d '\r')
		case "$line" in
			""|\#*|";"*) continue ;;
		esac
		if echo "$line" | grep -q '^\[.*\]$'; then
			if [ -n "$current" ] && [ -n "$strategy" ] && [ "$strategy" != "disabled" ]; then
				effective_mode="$filter_mode"
				if [ -z "$effective_mode" ]; then
					if [ -n "$hostlist" ]; then
						effective_mode="hostlist"
					elif [ -n "$ipset" ]; then
						effective_mode="ipset"
					else
						effective_mode="none"
					fi
				fi
				case "$effective_mode" in
					ipset) filter_file="$ipset" ;;
					hostlist) filter_file="$hostlist" ;;
					*) filter_file="" ;;
				esac
				cat_opts=$(build_category_opts "$protocol" "$effective_mode" "$filter_file" "$strategy")
				if [ -n "$cat_opts" ]; then
					if [ "$first" -eq 0 ]; then
						opts="$opts --new"
					fi
					opts="$opts $cat_opts"
					first=0
				fi
			fi
			current=${line#\[}
			current=${current%\]}
			protocol="tcp"
			hostlist=""
			ipset=""
			filter_mode=""
			strategy=""
			continue
		fi
		if echo "$line" | grep -q '^[a-z_]*='; then
			key=$(printf "%s" "$line" | cut -d'=' -f1)
			value=$(printf "%s" "$line" | cut -d'=' -f2-)
			case "$key" in
				protocol) protocol="$value" ;;
				hostlist) hostlist="$value" ;;
				ipset) ipset="$value" ;;
				filter_mode) filter_mode="$value" ;;
				strategy) strategy="$value" ;;
			esac
		fi
	done < "$CATEGORIES_FILE"

	if [ -n "$current" ] && [ -n "$strategy" ] && [ "$strategy" != "disabled" ]; then
		effective_mode="$filter_mode"
		if [ -z "$effective_mode" ]; then
			if [ -n "$hostlist" ]; then
				effective_mode="hostlist"
			elif [ -n "$ipset" ]; then
				effective_mode="ipset"
			else
				effective_mode="none"
			fi
		fi
		case "$effective_mode" in
			ipset) filter_file="$ipset" ;;
			hostlist) filter_file="$hostlist" ;;
			*) filter_file="" ;;
		esac
		cat_opts=$(build_category_opts "$protocol" "$effective_mode" "$filter_file" "$strategy")
		if [ -n "$cat_opts" ]; then
			if [ "$first" -eq 0 ]; then
				opts="$opts --new"
			fi
			opts="$opts $cat_opts"
		fi
	fi

	printf "%s" "$opts"
}

get_category_value() {
	local section key
	section="$1"
	key="$2"
	[ -f "$CATEGORIES_FILE" ] || return 0
	while IFS= read -r line || [ -n "$line" ]; do
		line=$(printf "%s" "$line" | tr -d '\r')
		case "$line" in
			"[$section]") in_section=1; continue ;;
			"["*"]") [ "${in_section:-0}" = "1" ] && break ;;
		esac
		if [ "${in_section:-0}" = "1" ] && [ "${line%%=*}" = "$key" ]; then
			printf "%s\n" "${line#*=}"
			return 0
		fi
	done < "$CATEGORIES_FILE"
}

set_category_strategy() {
	local section value tmpfile
	section="$1"
	value="$2"
	tmpfile="$TMP_DIR/z24k-categories.tmp"
	mkdir -p "$TMP_DIR"
	[ -f "$CATEGORIES_FILE" ] || return 0
	in_section=0
	replaced=0
	while IFS= read -r line || [ -n "$line" ]; do
		line=$(printf "%s" "$line" | tr -d '\r')
		if [ "$line" = "[$section]" ]; then
			in_section=1
			replaced=0
			printf "%s\n" "$line" >> "$tmpfile"
			continue
		fi
		case "$line" in
			"["*"]")
				if [ "$in_section" -eq 1 ] && [ "$replaced" -eq 0 ]; then
					printf "strategy=%s\n" "$value" >> "$tmpfile"
				fi
				in_section=0
				replaced=0
				printf "%s\n" "$line" >> "$tmpfile"
				continue
				;;
		esac
		if [ "$in_section" -eq 1 ] && [ "${line%%=*}" = "strategy" ]; then
			printf "strategy=%s\n" "$value" >> "$tmpfile"
			replaced=1
			continue
		fi
		printf "%s\n" "$line" >> "$tmpfile"
	done < "$CATEGORIES_FILE"
	if [ "$in_section" -eq 1 ] && [ "$replaced" -eq 0 ]; then
		printf "strategy=%s\n" "$value" >> "$tmpfile"
	fi
	mv "$tmpfile" "$CATEGORIES_FILE"
}

list_strategies() {
	local file
	file="$1"
	[ -f "$file" ] || return 0
	while IFS= read -r line || [ -n "$line" ]; do
		line=$(printf "%s" "$line" | tr -d '\r')
		case "$line" in
			\[*\])
				line=${line#\[}
				line=${line%\]}
				[ -n "$line" ] && printf "%s\n" "$line"
				;;
		esac
	done < "$file"
}

fetch_category_lists() {
	local section hostlist ipset mode
	section="$1"
	hostlist=$(get_category_value "$section" "hostlist")
	ipset=$(get_category_value "$section" "ipset")
	mode=$(get_category_value "$section" "filter_mode")
	case "$mode" in
		ipset)
			[ -n "$ipset" ] && fetch "$LISTS_RAW/$ipset" "$LISTS_DIR/$ipset" || true
			;;
		hostlist)
			[ -n "$hostlist" ] && fetch "$LISTS_RAW/$hostlist" "$LISTS_DIR/$hostlist" || true
			;;
		none)
			;;
		*)
			if [ -n "$ipset" ]; then
				fetch "$LISTS_RAW/$ipset" "$LISTS_DIR/$ipset" || true
			elif [ -n "$hostlist" ]; then
				fetch "$LISTS_RAW/$hostlist" "$LISTS_DIR/$hostlist" || true
			fi
			;;
	esac
}

set_custom_domain() {
	local domain
	domain="$1"
	mkdir -p "$LISTS_DIR"
	printf "%s\n" "$domain" > "$LISTS_DIR/zapret-hosts-custom.txt"
}

check_access() {
	local url
	url="$1"
	if [ -z "$url" ]; then
		return
	fi
	if curl --tls-max 1.2 --max-time 2 -s -o /dev/null "$url"; then
		echo -e "${green}Есть ответ по TLS 1.2.${plain}"
	else
		echo -e "${yellow}Нет ответа по TLS 1.2.${plain}"
	fi
	if curl --tlsv1.3 --max-time 2 -s -o /dev/null "$url"; then
		echo -e "${green}Есть ответ по TLS 1.3.${plain}"
	else
		echo -e "${yellow}Нет ответа по TLS 1.3.${plain}"
	fi
}

supports_http3() {
	if ! need_cmd curl; then
		return 1
	fi
	curl -V 2>/dev/null | grep -qi http3
}

supports_http2() {
	if ! need_cmd curl; then
		return 1
	fi
	curl -V 2>/dev/null | grep -qi http2
}

test_tls() {
	local url
	url="$1"
	if [ -z "$url" ]; then
		return 1
	fi
	curl --tls-max 1.2 --max-time 3 --connect-timeout 3 -s -o /dev/null "$url" && return 0
	curl --tlsv1.3 --max-time 3 --connect-timeout 3 -s -o /dev/null "$url"
}

test_tcp_suite() {
	local url
	local ok
	url="$1"
	if [ -z "$url" ]; then
		return 1
	fi
	ok=1

	if curl --tls-max 1.2 --http1.1 --max-time 3 --connect-timeout 3 -s -o /dev/null "$url"; then
		echo -e "${green}TLS 1.2 (HTTP/1.1): OK${plain}"
	else
		echo -e "${yellow}TLS 1.2 (HTTP/1.1): FAIL${plain}"
		ok=0
	fi

	if curl --tlsv1.3 --http1.1 --max-time 3 --connect-timeout 3 -s -o /dev/null "$url"; then
		echo -e "${green}TLS 1.3 (HTTP/1.1): OK${plain}"
	else
		echo -e "${yellow}TLS 1.3 (HTTP/1.1): FAIL${plain}"
		ok=0
	fi

	if supports_http2; then
		if curl --http2 --max-time 3 --connect-timeout 3 -s -o /dev/null "$url"; then
			echo -e "${green}HTTP/2: OK${plain}"
		else
			echo -e "${yellow}HTTP/2: FAIL${plain}"
			ok=0
		fi
	else
		echo -e "${yellow}HTTP/2: FAIL (curl без HTTP/2)${plain}"
		ok=0
	fi

	[ "$ok" -eq 1 ]
}

test_http3() {
	local url
	url="$1"
	if [ -z "$url" ]; then
		return 1
	fi
	curl --http3-only --max-time 3 --connect-timeout 3 -s -o /dev/null "$url"
}

auto_pick_category() {
	local section proto label url ini_file tmpfile count idx strat prev found mode hostlist ipset filter_file
	section="$1"
	proto="$2"
	label="$3"

	if [ ! -s "$CATEGORIES_FILE" ]; then
		echo -e "${yellow}Файл категорий не найден. Выполните установку/обновление.${plain}"
		return 1
	fi
	case "$proto" in
		udp) ini_file_check="$STRAT_UDP_FILE" ;;
		stun) ini_file_check="$STRAT_STUN_FILE" ;;
		*) ini_file_check="$STRAT_TCP_FILE" ;;
		esac
	if [ ! -s "$ini_file_check" ]; then
		echo -e "${yellow}Файл стратегий не найден. Выполните установку/обновление.${plain}"
		return 1
	fi
	if [ ! -s "$BLOBS_FILE" ]; then
		echo -e "${yellow}Файл blobs не найден. Выполните установку/обновление.${plain}"
		return 1
	fi
	if [ -z "$url" ] && [ -n "$filter_file" ]; then
		url=$(last_nonempty_line_any "$LISTS_DIR/$filter_file")
		if [ -n "$url" ]; then
			case "$url" in
				http://*|https://*) ;;
				*) url="https://$url" ;;
			esac
		fi
	fi

	if ! need_cmd curl; then
		echo -e "${yellow}curl не найден. Автоподбор пропущен для ${label}.${plain}"
		return 1
	fi

	mkdir -p "$TMP_DIR"
	ensure_category_files
	ensure_blob_files
	mode=$(get_category_value "$section" "filter_mode")
	hostlist=$(get_category_value "$section" "hostlist")
	ipset=$(get_category_value "$section" "ipset")
	filter_file=""
	case "$mode" in
		ipset) filter_file="$ipset" ;;
		hostlist) filter_file="$hostlist" ;;
		*) filter_file="" ;;
	esac
	if [ -n "$filter_file" ] && [ ! -s "$LISTS_DIR/$filter_file" ]; then
		echo -e "${yellow}Список $LISTS_DIR/$filter_file не найден или пустой. Автоподбор пропущен для ${label}.${plain}"
		return 0
	fi

	case "$proto" in
		udp) ini_file="$STRAT_UDP_FILE" ;;
		stun) ini_file="$STRAT_STUN_FILE" ;;
		*) ini_file="$STRAT_TCP_FILE" ;;
	esac

	tmpfile="$TMP_DIR/z24k-strats-auto.list"
	list_strategies "$ini_file" > "$tmpfile"
	count=$(wc -l < "$tmpfile" 2>/dev/null || echo 0)
	if [ "$count" -le 0 ]; then
		echo -e "${yellow}Список стратегий пуст для ${label}.${plain}"
		return 1
	fi

	if [ "$proto" = "udp" ] && ! supports_http3; then
		strat=$(head -n 1 "$tmpfile" 2>/dev/null || true)
		if [ -z "$strat" ]; then
			echo -e "${yellow}Список стратегий пуст для ${label}.${plain}"
			return 1
		fi
		echo -e "${yellow}curl без HTTP/3. Применяю стратегию без проверки: ${label}.${plain}"
		set_category_strategy "$section" "$strat"
		set_kv Z24K_PRESET categories
		set_opt_block "$(preset_categories)"
		restart_service_timeout || true
		echo -e "${green}Стратегия применена для ${label}: ${strat}${plain}"
		return 0
	fi

	prev=$(get_category_value "$section" "strategy")
	found=0
	idx=0
	echo -e "${cyan}Автоподбор стратегии: ${green}${label}${plain}"
	while IFS= read -r strat || [ -n "$strat" ]; do
		idx=$((idx + 1))
		set_category_strategy "$section" "$strat"
		set_kv Z24K_PRESET categories
		set_opt_block "$(preset_categories)"
		log "Пробую ${label} #${idx}: ${strat}"
		restart_service_timeout || true
		if [ "$proto" = "udp" ]; then
			if test_http3 "$url"; then
				echo -e "${green}HTTP/3 OK: ${url}${plain}"
				found=1
				break
			else
				echo -e "${yellow}HTTP/3 FAIL: ${url}${plain}"
			fi
		else
			if test_tcp_suite "$url"; then
				echo -e "${green}TCP OK (TLS1.2/TLS1.3/HTTP2): ${url}${plain}"
				found=1
				break
			else
				echo -e "${yellow}TCP FAIL (TLS1.2/TLS1.3/HTTP2): ${url}${plain}"
			fi
		fi
	done < "$tmpfile"

	if [ "$found" -eq 1 ]; then
		echo -e "${green}Найдена стратегия для ${label}: ${strat}${plain}"
		return 0
	fi

	prev="${prev:-disabled}"
	set_category_strategy "$section" "$prev"
	set_kv Z24K_PRESET categories
	set_opt_block "$(preset_categories)"
	restart_service_timeout || true
	echo -e "${yellow}Стратегия для ${label} не найдена.${plain}"
	return 1
}

auto_pick_all_categories() {
		local ylist gvlist
		ylist="$LISTS_DIR/ipset-youtube.txt"
		gvlist="$LISTS_DIR/ipset-googlevideo.txt"
		if ! required_lists_ok; then
			echo -e "${yellow}Списки не найдены или пустые. Обновите списки и запустите автоподбор снова.${plain}"
			return 0
		fi
	echo -e "${cyan}Автоподбор стратегий для категорий...${plain}"
	auto_pick_category "youtube" "tcp" "YouTube TCP" "https://www.youtube.com/" || true
	auto_pick_category "youtube_udp" "udp" "YouTube UDP" "https://www.youtube.com/" || true
	auto_pick_category "googlevideo_tcp" "tcp" "Googlevideo" "" || true
	auto_pick_category "rkn" "tcp" "RKN" "https://meduza.io/" || true
	echo -e "${cyan}Автоподбор завершен.${plain}"
}

required_lists_ok() {
	ylist="$LISTS_DIR/ipset-youtube.txt"
	gvlist="$LISTS_DIR/ipset-googlevideo.txt"
	[ -s "$ylist" ] && [ -s "$gvlist" ]
}

pick_strategy_interactive() {
	local section proto label url ini_file tmpfile count idx start strat prev
	section="$1"
	proto="$2"
	label="$3"

	if [ ! -s "$CATEGORIES_FILE" ]; then
		echo -e "${yellow}Файл категорий не найден. Выполните установку/обновление.${plain}"
		pause_enter
		return
	fi
	url="$4"
	mkdir -p "$TMP_DIR"

	case "$proto" in
		udp) ini_file="$STRAT_UDP_FILE" ;;
		stun) ini_file="$STRAT_STUN_FILE" ;;
		*) ini_file="$STRAT_TCP_FILE" ;;
	esac

	tmpfile="$TMP_DIR/z24k-strats.list"
	list_strategies "$ini_file" > "$tmpfile"
	count=$(wc -l < "$tmpfile" 2>/dev/null || echo 0)
	if [ "$count" -le 0 ]; then
		echo -e "${yellow}Список стратегий пуст.${plain}"
		pause_enter
		return
	fi

	echo -e "${cyan}Подбор стратегии: ${green}$label${plain}"
	read_tty "Номер стратегии (1-$count, Enter=1): " start
	[ -z "$start" ] && start=1
	prev=$(get_category_value "$section" "strategy")
	idx=0

	ensure_blob_files

	while IFS= read -r strat || [ -n "$strat" ]; do
		idx=$((idx + 1))
		[ "$idx" -lt "$start" ] && continue
		set_category_strategy "$section" "$strat"
		set_kv Z24K_PRESET categories
		set_opt_block "$(preset_categories)"
		log "Перезапуск сервиса..."
		restart_service_timeout || true
		echo -e "${cyan}Стратегия #${idx}: ${green}${strat}${plain}"
		check_access "$url"
		read_tty "1=сохранить, 0=отмена, Enter=следующая: " ans
		case "$ans" in
			1)
				echo -e "${green}Сохранено.${plain}"
				pause_enter
				return
				;;
			0)
				[ -n "$prev" ] && set_category_strategy "$section" "$prev"
				set_kv Z24K_PRESET categories
				set_opt_block "$(preset_categories)"
				restart_service_timeout || true
				echo -e "${yellow}Отмена.${plain}"
				pause_enter
				return
				;;
		esac
	done < "$tmpfile"

	echo -e "${yellow}Стратегии закончились.${plain}"
	pause_enter
}

magisk_pick_menu() {
	local domain url
	while true; do
		safe_clear
		echo -e "${cyan}--- Подбор стратегий (как magisk) ---${plain}"
		echo "1. YouTube UDP (QUIC)"
		echo "2. YouTube TCP"
		echo "3. Googlevideo (YT поток)"
		echo "4. RKN"
		echo "5. Пользовательский домен"
		echo "0. Назад"
		echo ""
		read_tty "Ваш выбор: " ans
		case "$ans" in
			1) pick_strategy_interactive "youtube_udp" "udp" "YouTube UDP" "https://www.youtube.com/" ;;
			2) pick_strategy_interactive "youtube" "tcp" "YouTube TCP" "https://www.youtube.com/" ;;
			3)
				read_tty "URL для проверки (Enter=rr1---sn-jvhnu5g-n8vr.googlevideo.com): " url
				[ -z "$url" ] && url="https://rr1---sn-jvhnu5g-n8vr.googlevideo.com"
				pick_strategy_interactive "googlevideo_tcp" "tcp" "Googlevideo" "$url"
				;;
			4) pick_strategy_interactive "rkn" "tcp" "RKN" "https://meduza.io/" ;;
			5)
				read_tty "Домен: " domain
				[ -z "$domain" ] && continue
				set_custom_domain "$domain"
				pick_strategy_interactive "custom" "tcp" "Custom" "https://$domain/"
				;;
			0|"") return ;;
		esac
	done
}

show_category_strategies() {
	local s
	echo -e "${cyan}--- Стратегии категорий ---${plain}"
	s=$(get_category_value "youtube" "strategy")
	echo "YouTube TCP: ${s:-disabled}"
	s=$(get_category_value "youtube_udp" "strategy")
	echo "YouTube UDP: ${s:-disabled}"
	s=$(get_category_value "googlevideo_tcp" "strategy")
	echo "Googlevideo: ${s:-disabled}"
	s=$(get_category_value "rkn" "strategy")
	echo "RKN: ${s:-disabled}"
	s=$(get_category_value "custom" "strategy")
	echo "Custom: ${s:-disabled}"
}

show_category_command() {
	local opt
	echo -e "${cyan}--- NFQWS2_OPT (Категории) ---${plain}"
	ensure_category_files
	ensure_blob_files
	sync_category_lists
	opt=$(build_opt_from_categories)
	if [ -n "$opt" ]; then
		printf "%s\n" "$opt"
	else
		echo -e "${yellow}Пусто. Категории не собраны.${plain}"
	fi
}

restart_service_timeout() {
	local pid i
	"$SERVICE" restart >/tmp/z24k-restart.log 2>&1 &
	pid=$!
	i=0
	while kill -0 "$pid" 2>/dev/null; do
		i=$((i + 1))
		if [ "$i" -ge 30 ]; then
			log "Restart timed out. See /tmp/z24k-restart.log"
			kill "$pid" 2>/dev/null || true
			return 1
		fi
		sleep 1
	done
	wait "$pid" 2>/dev/null || true
	return 0
}

ensure_rkn_bootstrap_hosts() {
	local f
	f="$INSTALL_DIR/ipset/zapret-hosts-user.txt"
	mkdir -p "$INSTALL_DIR/ipset"
	[ -f "$f" ] || : > "$f"
	grep -q '^antizapret\.prostovpn\.org$' "$f" 2>/dev/null || echo "antizapret.prostovpn.org" >> "$f"
	grep -q '^prostovpn\.org$' "$f" 2>/dev/null || echo "prostovpn.org" >> "$f"
	grep -q '^raw\.githubusercontent\.com$' "$f" 2>/dev/null || echo "raw.githubusercontent.com" >> "$f"
}

update_rkn_list() {
	local urls url tmpfile zdom ok tmpbase
	if [ -f "$INSTALL_DIR/ipset/def.sh" ]; then
		ZAPRET_BASE="$INSTALL_DIR" ZAPRET_RW="$INSTALL_DIR" . "$INSTALL_DIR/ipset/def.sh"
	else
		echo -e "${yellow}RKN updater not found.${plain}"
		return 1
	fi

	if [ -f "$INSTALL_DIR/domains-export.txt" ]; then
		log "Using local RKN list: $INSTALL_DIR/domains-export.txt"
		if [ -s "$INSTALL_DIR/domains-export.txt" ]; then
			sort -u "$INSTALL_DIR/domains-export.txt" | zz "$ZHOSTLIST"
			hup_zapret_daemons
			return 0
		fi
	fi

	if [ -n "$Z24K_RKN_URLS" ]; then
		urls="$Z24K_RKN_URLS"
	else
		urls="$Z24K_RAW/domains-export.txt \
https://antizapret.prostovpn.org:8443/domains-export.txt \
https://antizapret.prostovpn.org/domains-export.txt"
	fi

	log "Updating RKN list (bundled+mirrors)"
	ok=0
	tmpbase="${TMPDIR:-$TMP_DIR}"
	mkdir -p "$tmpbase"
	tmpfile="$tmpbase/zapret.txt.gz"
	zdom="$tmpbase/zapret.txt"

	for url in $urls; do
		rm -f "$tmpfile" "$zdom"
		log "Downloading: $url"
		if curl -k --fail --connect-timeout 5 --max-time 25 --retry 2 "$url" -o "$tmpfile"; then
			if gunzip -t "$tmpfile" >/dev/null 2>&1; then
				gunzip -c "$tmpfile" > "$zdom" || true
			else
				cp -f "$tmpfile" "$zdom"
			fi
			if [ -s "$zdom" ]; then
				sort -u "$zdom" | zz "$ZHOSTLIST"
				ok=1
				break
			fi
		fi
	done

	rm -f "$tmpfile" "$zdom"
	if [ "$ok" -eq 1 ]; then
		hup_zapret_daemons
		return 0
	fi

	echo -e "${yellow}RKN list update failed (all mirrors).${plain}"
	return 1
}

is_installed() {
	[ -f "$CONFIG" ] && [ -x "$SERVICE" ]
}

show_status() {
	local preset enable running installed
	preset=$(get_kv Z24K_PRESET)
	enable=$(get_kv NFQWS2_ENABLE)
	[ -z "$preset" ] && preset="unknown"
	[ -z "$enable" ] && enable="unknown"

	if is_installed; then
		installed="yes"
	else
		installed="no"
	fi

	running="stopped"
	if ps 2>/dev/null | grep -v grep | grep -q "nfqws2"; then
		running="running"
	fi

	echo -e "${cyan}--- Статус ---${plain}"
	echo "Установлено: $installed"
	echo "Пресет: $preset"
	echo "NFQWS2_ENABLE: $enable"
	echo "nfqws2: $running"
}

menu() {
	safe_clear
	echo -e "${cyan}--- z24k меню ---${plain}"
	show_status
	echo ""
	menu_item "1" "Установка/Обновление" ""
	menu_item "2" "Удаление" ""
	if is_installed; then
		menu_item "3" "Стратегия: Категории (community)" ""
		menu_item "4" "Обновить все списки" ""
		menu_item "5" "Редактировать категории" ""
		menu_item "6" "Подбор стратегий (как magisk)" ""
		menu_item "7" "Запустить blockcheck2 (интерактивно)" ""
		menu_item "8" "Тест стратегий (авто)" ""
		menu_item "9" "Обновить список RKN" ""
		menu_item "10" "Вкл/Выкл NFQWS2" ""
		menu_item "11" "Перезапуск сервиса" ""
		menu_item "12" "Показать статус" ""
		menu_item "13" "Показать стратегии категорий" ""
		menu_item "14" "Показать NFQWS2_OPT (категории)" ""
		menu_item "15" "Редактировать config" ""
	fi
	menu_item "0" "Выход" ""
	echo ""
	read_tty "Ваш выбор: " ans

	case "$ans" in
		1) do_install ;;
		2) do_uninstall ;;
		3) is_installed && apply_preset "categories" "$(preset_categories)" ;;
		4) is_installed && sync_all_lists && pause_enter ;;
		5) is_installed && ensure_category_files && ${EDITOR:-vi} "$CATEGORIES_FILE" ;;
		6) is_installed && magisk_pick_menu ;;
		7) is_installed && run_blockcheck ;;
		8) is_installed && test_strategies ;;
		9)
			if is_installed; then
				log "RKN list update is disabled in category mode."
				pause_enter
			fi
			;;
		10) is_installed && toggle_nfqws2 ;;
		11) is_installed && restart_service && pause_enter ;;
		12) show_status && pause_enter ;;
		13) show_category_strategies && pause_enter ;;
		14) show_category_command && pause_enter ;;
		15) is_installed && ${EDITOR:-vi} "$CONFIG" ;;
		0|"") exit 0 ;;
		*) echo -e "${yellow}Неверный ввод.${plain}"; sleep 1 ;;
	esac

	menu
}

log "Menu version $SCRIPT_VERSION"
menu
