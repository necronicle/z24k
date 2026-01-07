#!/bin/sh
set -e

SCRIPT_VERSION="2026-01-07-4"
DEFAULT_VER="0.8.2"
REPO="bol-van/zapret2"
Z24K_RAW="https://github.com/necronicle/z24k/raw/master"
KEENETIC_REPO_RAW="$Z24K_RAW/keenetic"
INSTALL_DIR="/opt/zapret2"
TMP_DIR="/tmp/zapret2-install"
HAD_CONFIG=0

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
		HAD_CONFIG=1
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

set_kv() {
	key="$1"
	val="$2"
	if grep -q "^${key}=" "$INSTALL_DIR/config"; then
		sed -i "s|^${key}=.*|${key}=${val}|" "$INSTALL_DIR/config"
	else
		echo "${key}=${val}" >> "$INSTALL_DIR/config"
	fi
}

install_menu() {
	log "Installing menu"
	fetch "$Z24K_RAW/z24k.sh" "$INSTALL_DIR/z24k.sh" || true
	if [ ! -f "$INSTALL_DIR/z24k.sh" ]; then
		cat <<'EOF' > "$INSTALL_DIR/z24k.sh"
#!/bin/sh
set -e

CONFIG="/opt/zapret2/config"
CONFIG_DEFAULT="/opt/zapret2/config.default"
SERVICE="/opt/zapret2/init.d/sysv/zapret2"

plain='\033[0m'
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
cyan='\033[0;36m'

pause_enter() {
  read -re -p "Enter для продолжения" _
}

menu_item() {
  echo -e "${green}$1. $2${plain} $3"
}

need_config() {
	if [ ! -f "$CONFIG" ]; then
		echo "Config not found: $CONFIG" >&2
		exit 1
	fi
}

set_kv() {
	key="$1"
	val="$2"
	if grep -q "^${key}=" "$CONFIG"; then
		sed -i "s|^${key}=.*|${key}=${val}|" "$CONFIG"
	else
		echo "${key}=${val}" >> "$CONFIG"
	fi
}

get_kv() {
	key="$1"
	grep "^${key}=" "$CONFIG" | tail -n1 | cut -d= -f2-
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
	awk -v opt="$opt" '
		BEGIN {found=0; in=0}
		{
			if ($0 ~ /^NFQWS2_OPT="/) {
				found=1
				print "NFQWS2_OPT=\""
				print opt
				print "\""
				in=1
				next
			}
			if (in) {
				if ($0 ~ /^"$/) in=0
				next
			}
			print
		}
		END {
			if (!found) {
				print ""
				print "NFQWS2_OPT=\""
				print opt
				print "\""
			}
		}
	' "$CONFIG" > "${CONFIG}.tmp" && mv "${CONFIG}.tmp" "$CONFIG"
}

restart_service() {
	if [ -x "$SERVICE" ]; then
		"$SERVICE" restart
	else
		echo "Service not found: $SERVICE" >&2
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

preset_default() {
	if [ -f "$CONFIG_DEFAULT" ]; then
		get_opt_block "$CONFIG_DEFAULT"
	else
		cat <<'EOS'
--filter-tcp=80 --filter-l7=http <HOSTLIST> --payload=http_req --lua-desync=fake:blob=fake_default_http:tcp_md5 --lua-desync=multisplit:pos=method+2 --new
--filter-tcp=443 --filter-l7=tls <HOSTLIST> --payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls:tcp_md5:tcp_seq=-10000 --lua-desync=multidisorder:pos=1,midsld --new
--filter-udp=443 --filter-l7=quic <HOSTLIST_NOAUTO> --payload=quic_initial --lua-desync=fake:blob=fake_default_quic:repeats=6
EOS
	fi
}

preset_aggressive() {
	cat <<'EOS'
--filter-tcp=80 --filter-l7=http <HOSTLIST> --payload=http_req --lua-desync=fake:blob=fake_default_http:tcp_md5:ip_autottl=-2,3-20 --lua-desync=fakedsplit:ip_autottl=-2,3-20:tcp_md5 --new
--filter-tcp=443 --filter-l7=tls <HOSTLIST> --payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls:tcp_md5:repeats=11:tls_mod=rnd,dupsid,padencap --lua-desync=multidisorder:pos=midsld --new
--filter-udp=443 --filter-l7=quic <HOSTLIST_NOAUTO> --payload=quic_initial --lua-desync=fake:blob=fake_default_quic:repeats=11
EOS
}

preset_minimal() {
	cat <<'EOS'
--filter-tcp=80 --filter-l7=http <HOSTLIST> --payload=http_req --lua-desync=fake:blob=fake_default_http:tcp_md5 --lua-desync=multisplit:pos=method+2 --new
--filter-tcp=443 --filter-l7=tls <HOSTLIST> --payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls:tcp_md5:tcp_seq=-10000 --lua-desync=multidisorder:pos=1,midsld
EOS
}

show_status() {
	local preset enable running
	preset=$(get_kv Z24K_PRESET)
	enable=$(get_kv NFQWS2_ENABLE)
	[ -z "$preset" ] && preset="unknown"
	[ -z "$enable" ] && enable="unknown"

	echo -e "${cyan}--- Статус ---${plain}"
	echo "Preset: $preset"
	echo "NFQWS2_ENABLE: $enable"
	ps | grep -v grep | grep nfqws2 >/dev/null 2>&1 && running="${green}running${plain}" || running="${red}stopped${plain}"
	echo -e "nfqws2: $running"
}

toggle_nfqws2() {
	local cur
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

menu() {
	need_config
	while :; do
		clear
		echo -e "${cyan}--- z24k меню ---${plain}"
		show_status
		echo ""
		menu_item "1" "Стратегия: Default" ""
		menu_item "2" "Стратегия: Aggressive" ""
		menu_item "3" "Стратегия: Minimal (без QUIC)" ""
		menu_item "4" "Вкл/Выкл NFQWS2" ""
		menu_item "5" "Перезапуск сервиса" ""
		menu_item "6" "Показать статус" ""
		menu_item "7" "Редактировать config" ""
		menu_item "0" "Выход" ""
		echo ""
		read -re -p "Ваш выбор: " ans
		case "$ans" in
			1) apply_preset "default" "$(preset_default)" ;;
			2) apply_preset "aggressive" "$(preset_aggressive)" ;;
			3) apply_preset "minimal" "$(preset_minimal)" ;;
			4) toggle_nfqws2 ;;
			5) restart_service; pause_enter ;;
			6) show_status; pause_enter ;;
			7) ${EDITOR:-vi} "$CONFIG" ;;
			0|"") exit 0 ;;
			*) echo -e "${yellow}Неверный ввод.${plain}"; sleep 1 ;;
		esac
	done
}

menu
EOF
	fi
	chmod +x "$INSTALL_DIR/z24k.sh"
	mkdir -p /opt/bin
	ln -sf "$INSTALL_DIR/z24k.sh" /opt/bin/z24k
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
	install_menu

	if [ "$HAD_CONFIG" -eq 0 ]; then
		sed -i 's/^NFQWS2_ENABLE=0/NFQWS2_ENABLE=1/' "$INSTALL_DIR/config"
		set_kv Z24K_PRESET default
	fi

	if [ -x /opt/etc/init.d/S00fix ]; then
		/opt/etc/init.d/S00fix start || true
	fi

	"$INSTALL_DIR/init.d/sysv/zapret2" restart
	log "Done. Edit $INSTALL_DIR/config if needed."

	if [ "$HAD_CONFIG" -eq 0 ] && [ -t 0 ]; then
		"$INSTALL_DIR/z24k.sh"
	fi
}

main "$@"
