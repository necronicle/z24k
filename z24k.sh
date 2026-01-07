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

preset_minimal() {
	cat <<'EOF'
--filter-tcp=80 --filter-l7=http <HOSTLIST> --payload=http_req --lua-desync=fake:blob=fake_default_http:tcp_md5 --lua-desync=multisplit:pos=method+2 --new
--filter-tcp=443 --filter-l7=tls <HOSTLIST> --payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls:tcp_md5:tcp_seq=-10000 --lua-desync=multidisorder:pos=1,midsld
EOF
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
