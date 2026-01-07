#!/bin/sh
set -e

SCRIPT_VERSION="2026-01-07-16"
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

preset_aggressive() {
	cat <<'EOF'
--filter-tcp=80 --filter-l7=http <HOSTLIST> --payload=http_req --lua-desync=fake:blob=fake_default_http:tcp_md5:ip_autottl=-2,3-20 --lua-desync=fakedsplit:ip_autottl=-2,3-20:tcp_md5 --new
--filter-tcp=443 --filter-l7=tls <HOSTLIST> --payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls:tcp_md5:repeats=11:tls_mod=rnd,dupsid,padencap --lua-desync=multidisorder:pos=midsld --new
--filter-udp=443 --filter-l7=quic <HOSTLIST_NOAUTO> --payload=quic_initial --lua-desync=fake:blob=fake_default_quic:repeats=11
EOF
}

preset_universal() {
	cat <<'EOF'
--filter-tcp=80 --filter-l7=http <HOSTLIST> --payload=http_req --lua-desync=fake:blob=fake_default_http:ip_autottl=-2,3-20:ip6_autottl=-2,3-20:tcp_md5 --lua-desync=fakedsplit:ip_autottl=-2,3-20:ip6_autottl=-2,3-20:tcp_md5 --new
--filter-tcp=443 --filter-l7=tls <HOSTLIST> --payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls:tcp_md5:tcp_seq=-10000:repeats=6 --lua-desync=multidisorder:pos=midsld --new
--filter-udp=443 --filter-l7=quic <HOSTLIST_NOAUTO> --payload=quic_initial --lua-desync=fake:blob=fake_default_quic:repeats=11
EOF
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
	set_opt_block "$opt"
	set_kv NFQWS2_ENABLE 1
	set_kv Z24K_PRESET "$name"
	restart_service
	echo -e "${green}Готово.${plain}"
	pause_enter
}

test_url() {
	url="$1"
	code=$(curl -k --max-time 8 --connect-timeout 5 -s -o /dev/null -w "%{http_code}" "$url")
	rc=$?
	if [ "$rc" -ne 0 ] || [ "$code" = "000" ]; then
		printf "%-50s %s\n" "$url" "FAIL"
	elif [ "$code" -ge 200 ] && [ "$code" -lt 400 ]; then
		printf "%-50s %s\n" "$url" "OK ($code)"
	else
		printf "%-50s %s\n" "$url" "WARN ($code)"
	fi
}

test_strategies() {
	if ! need_cmd curl; then
		echo "curl is required for tests."
		pause_enter
		return
	fi
	set_mode_hostlist
	ensure_hostlist_file
	log "Preparing hostlist"
	update_user_lists >/dev/null 2>&1 || true
	urls="https://www.youtube.com/ https://discord.com/ https://discord.gg/ https://antizapret.prostovpn.org:8443/domains-export.txt https://antizapret.prostovpn.org/domains-export.txt"
	for name in universal default aggressive minimal; do
		ok=0
		total=0
		echo -e "${cyan}Testing: ${green}${name}${plain}"
		case "$name" in
			universal) apply_preset_quiet "$name" "$(preset_universal)" ;;
			default) apply_preset_quiet "$name" "$(preset_default)" ;;
			aggressive) apply_preset_quiet "$name" "$(preset_aggressive)" ;;
			minimal) apply_preset_quiet "$name" "$(preset_minimal)" ;;
		esac
		for url in $urls; do
			total=$((total + 1))
			out=$(test_url "$url")
			echo "$out"
			echo "$out" | grep -q "OK (" && ok=$((ok + 1))
		done
		echo -e "${green}Result:${plain} ${ok}/${total} OK"
		echo ""
	done
	pause_enter
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
}

update_rkn_list() {
	local urls url tmpfile zdom ok tmpbase
	if [ -f "$INSTALL_DIR/ipset/def.sh" ]; then
		ZAPRET_BASE="$INSTALL_DIR" ZAPRET_RW="$INSTALL_DIR" . "$INSTALL_DIR/ipset/def.sh"
	else
		echo -e "${yellow}RKN updater not found.${plain}"
		return 1
	fi

	if [ -n "$Z24K_RKN_URLS" ]; then
		urls="$Z24K_RKN_URLS"
	else
		urls="https://antizapret.prostovpn.org:8443/domains-export.txt \
https://antizapret.prostovpn.org/domains-export.txt"
	fi

	log "Updating RKN list (mirrors)"
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
	local preset enable running
	preset=$(get_kv Z24K_PRESET)
	enable=$(get_kv NFQWS2_ENABLE)
	[ -z "$preset" ] && preset="unknown"
	[ -z "$enable" ] && enable="unknown"

	echo -e "${cyan}--- Статус ---${plain}"
	if is_installed; then
		echo "Installed: yes"
	else
		echo "Installed: no"
	fi
	echo "Preset: $preset"
	echo "NFQWS2_ENABLE: $enable"
	ps | grep -v grep | grep nfqws2 >/dev/null 2>&1 && running="${green}running${plain}" || running="${red}stopped${plain}"
	echo -e "nfqws2: $running"
}

menu() {
	while :; do
		safe_clear
		echo -e "${cyan}--- z24k меню ---${plain}"
		show_status
		echo ""

		menu_item "1" "Установка/Обновление" ""
		menu_item "2" "Удаление" ""
		if is_installed; then
			menu_item "3" "Стратегия: Universal (auto TTL)" ""
			menu_item "4" "Стратегия: Default" ""
			menu_item "5" "Стратегия: Aggressive" ""
			menu_item "6" "Стратегия: Minimal (без QUIC)" ""
			menu_item "7" "Тест стратегий (авто)" ""
			menu_item "8" "Обновить списки YT/Discord" ""
			menu_item "9" "Обновить список RKN" ""
			menu_item "10" "Вкл/Выкл NFQWS2" ""
			menu_item "11" "Перезапуск сервиса" ""
			menu_item "12" "Показать статус" ""
			menu_item "13" "Редактировать config" ""
			menu_item "0" "Выход" ""
		else
			menu_item "0" "Выход" ""
		fi
		echo ""
		read_tty "Ваш выбор: " ans

		case "$ans" in
			1) do_install ;;
			2) do_uninstall ;;
			3) is_installed && apply_preset "universal" "$(preset_universal)" ;;
			4) is_installed && apply_preset "default" "$(preset_default)" ;;
			5) is_installed && apply_preset "aggressive" "$(preset_aggressive)" ;;
			6) is_installed && apply_preset "minimal" "$(preset_minimal)" ;;
			7) is_installed && test_strategies ;;
			8) is_installed && set_mode_hostlist && update_user_lists && restart_service && pause_enter ;;
			9) is_installed && set_mode_hostlist && ensure_rkn_bootstrap_hosts && restart_service && { update_rkn_list || log "RKN update failed. You can retry from the menu."; } && restart_service && pause_enter ;;
			10) is_installed && toggle_nfqws2 ;;
			11) is_installed && restart_service && pause_enter ;;
			12) show_status && pause_enter ;;
			13) is_installed && ${EDITOR:-vi} "$CONFIG" ;;
			0|"") exit 0 ;;
			*) echo -e "${yellow}Неверный ввод.${plain}"; sleep 1 ;;
		esac
	done
}

log "Menu version $SCRIPT_VERSION"
menu
