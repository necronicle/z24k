#!/bin/sh
set -e

SCRIPT_VERSION="2026-01-07-32"
DEFAULT_VER="0.8.2"
REPO="bol-van/zapret2"
Z24K_REPO="necronicle/z24k"
Z24K_RAW="https://raw.githubusercontent.com/$Z24K_REPO/master"
KEENETIC_RAW="$Z24K_RAW/keenetic"
LISTS_RAW="$Z24K_RAW/lists"
INSTALL_DIR="/opt/zapret2"
TMP_DIR="/tmp/zapret2-install"

CONFIG="$INSTALL_DIR/config"
CONFIG_DEFAULT="$INSTALL_DIR/config.default"
SERVICE="$INSTALL_DIR/init.d/sysv/zapret2"

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
		curl -fsSL --connect-timeout 5 --max-time 20 --retry 1 "$url" -o "$out"
	elif need_cmd wget; then
		wget -qO "$out" --dns-timeout=5 --connect-timeout=5 --read-timeout=20 "$url"
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

	if [ "$HAD_CONFIG" -eq 0 ]; then
		sed -i 's/^NFQWS2_ENABLE=0/NFQWS2_ENABLE=1/' "$CONFIG"
		set_kv Z24K_PRESET universal
		set_mode_hostlist
	fi

	if [ -x /opt/etc/init.d/S00fix ]; then
		/opt/etc/init.d/S00fix start || true
	fi

	update_user_lists
	"$SERVICE" restart
	if ! update_rkn_list; then
		log "RKN update failed. You can retry from the menu."
	fi

	"$SERVICE" restart
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

extract_blockcheck_strategy() {
	testname="$1"
	logfile="$2"
	line=$(grep -F "working strategy found" "$logfile" | grep -F "$testname" | tail -n1)
	[ -n "$line" ] || return 1
	strategy=$(echo "$line" | sed -e 's/^.*: [^ ]* //' -e 's/ !!!!!$//' -e 's/^nfqws2 //' -e 's/^dvtws2 //' -e 's/^winws2 //' | xargs)
	[ -n "$strategy" ] || return 1
	printf "%s" "$strategy"
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
	domain=""
	logfile="${TMPDIR:-/tmp}/z24k-blockcheck-${list_key}.log"

	ensure_split_hostlists
	domain=$(last_nonempty_line "$list_file")
	if [ -z "$domain" ]; then
		echo -e "${yellow}Список пустой: $list_file${plain}"
		pause_enter
		return
	fi

	if [ -x "$SERVICE" ]; then
		"$SERVICE" stop || true
	fi

	echo -e "${cyan}Подбор стратегии для ${green}${label}${plain} (${domain})"
	ZAPRET_BASE="$INSTALL_DIR" ZAPRET_RW="$INSTALL_DIR" BATCH=1 TEST=standard DOMAINS="$domain" IPVS=4 \
		sh "$INSTALL_DIR/blockcheck2.sh" >"$logfile" 2>&1

	http_strat=$(extract_blockcheck_strategy "curl_test_http" "$logfile" || true)
	tls13_strat=$(extract_blockcheck_strategy "curl_test_https_tls13" "$logfile" || true)
	tls12_strat=$(extract_blockcheck_strategy "curl_test_https_tls12" "$logfile" || true)
	quic_strat=$(extract_blockcheck_strategy "curl_test_http3" "$logfile" || true)

	tls_strat="$tls13_strat"
	[ -z "$tls_strat" ] && tls_strat="$tls12_strat"

	if [ -z "$http_strat" ] && [ -z "$tls_strat" ] && [ -z "$quic_strat" ]; then
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
	for name in universal default manual manual_blobs aggressive minimal; do
		ok=0
		total=0
		echo -e "${cyan}Testing: ${green}${name}${plain}"
		case "$name" in
			universal) apply_preset_quiet "$name" "$(preset_universal)" ;;
			default) apply_preset_quiet "$name" "$(preset_default)" ;;
			manual) apply_preset_quiet "$name" "$(preset_manual)" ;;
			manual_blobs) apply_preset_quiet "$name" "$(preset_manual_blobs)" ;;
			aggressive) apply_preset_quiet "$name" "$(preset_aggressive)" ;;
			minimal) apply_preset_quiet "$name" "$(preset_minimal)" ;;
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
		menu_item "3" "Стратегия: Universal (split lists)" ""
		menu_item "4" "Стратегия: Default" ""
		menu_item "5" "Стратегия: Manual" ""
		menu_item "6" "Стратегия: Manual+Blobs" ""
		menu_item "7" "Стратегия: Aggressive" ""
		menu_item "8" "Стратегия: Minimal (без QUIC)" ""
		menu_item "9" "Автоподбор стратегии: YouTube" ""
		menu_item "10" "Автоподбор стратегии: Discord" ""
		menu_item "11" "Автоподбор стратегии: RKN" ""
		menu_item "12" "Запустить blockcheck2 (интерактивно)" ""
		menu_item "13" "Тест стратегий (авто)" ""
		menu_item "14" "Обновить списки YT/Discord" ""
		menu_item "15" "Обновить список RKN" ""
		menu_item "16" "Вкл/Выкл NFQWS2" ""
		menu_item "17" "Перезапуск сервиса" ""
		menu_item "18" "Показать статус" ""
		menu_item "19" "Редактировать config" ""
	fi
	menu_item "0" "Выход" ""
	echo ""
	read_tty "Ваш выбор: " ans

	case "$ans" in
		1) do_install ;;
		2) do_uninstall ;;
		3) is_installed && apply_preset "universal" "$(preset_universal)" ;;
		4) is_installed && apply_preset "default" "$(preset_default)" ;;
		5) is_installed && apply_preset "manual" "$(preset_manual)" ;;
		6) is_installed && apply_preset "manual_blobs" "$(preset_manual_blobs)" ;;
		7) is_installed && apply_preset "aggressive" "$(preset_aggressive)" ;;
		8) is_installed && apply_preset "minimal" "$(preset_minimal)" ;;
		9) is_installed && auto_pick_strategy "yt" "$INSTALL_DIR/ipset/zapret-hosts-youtube.txt" "YouTube" ;;
		10) is_installed && auto_pick_strategy "ds" "$INSTALL_DIR/ipset/zapret-hosts-discord.txt" "Discord" ;;
		11) is_installed && auto_pick_strategy "rkn" "$INSTALL_DIR/ipset/zapret-hosts.txt" "RKN" ;;
		12) is_installed && run_blockcheck ;;
		13) is_installed && test_strategies ;;
		14) is_installed && set_mode_hostlist && update_user_lists && restart_service && pause_enter ;;
		15)
			if is_installed; then
				set_mode_hostlist
				ensure_rkn_bootstrap_hosts
				restart_service
				if ! update_rkn_list; then
					log "RKN update failed. You can retry from the menu."
				fi
				restart_service
				pause_enter
			fi
			;;
		16) is_installed && toggle_nfqws2 ;;
		17) is_installed && restart_service && pause_enter ;;
		18) show_status && pause_enter ;;
		19) is_installed && ${EDITOR:-vi} "$CONFIG" ;;
		0|"") exit 0 ;;
		*) echo -e "${yellow}Неверный ввод.${plain}"; sleep 1 ;;
	esac

	menu
}

log "Menu version $SCRIPT_VERSION"
menu
