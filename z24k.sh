#!/bin/sh
set -e

CONFIG="/opt/zapret2/config"
CONFIG_DEFAULT="/opt/zapret2/config.default"
SERVICE="/opt/zapret2/init.d/sysv/zapret2"

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
	echo "Applying preset: $name"
	set_opt_block "$opt"
	set_kv NFQWS2_ENABLE 1
	restart_service
	echo "Done."
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
	echo "NFQWS2_ENABLE: $(grep '^NFQWS2_ENABLE=' "$CONFIG" | tail -n1)"
	echo "NFQWS2_PORTS_TCP: $(grep '^NFQWS2_PORTS_TCP=' "$CONFIG" | tail -n1)"
	echo "NFQWS2_PORTS_UDP: $(grep '^NFQWS2_PORTS_UDP=' "$CONFIG" | tail -n1)"
	ps | grep -v grep | grep nfqws2 || true
}

menu() {
	need_config
	while :; do
		echo ""
		echo "z24k menu"
		echo "1) Apply default strategy"
		echo "2) Apply aggressive strategy"
		echo "3) Apply minimal strategy (no QUIC)"
		echo "4) Disable nfqws2"
		echo "5) Restart service"
		echo "6) Show status"
		echo "7) Edit config"
		echo "0) Exit"
		printf "> "
		read -r choice
		case "$choice" in
			1) apply_preset "default" "$(preset_default)" ;;
			2) apply_preset "aggressive" "$(preset_aggressive)" ;;
			3) apply_preset "minimal" "$(preset_minimal)" ;;
			4) set_kv NFQWS2_ENABLE 0; restart_service ;;
			5) restart_service ;;
			6) show_status ;;
			7) ${EDITOR:-vi} "$CONFIG" ;;
			0) exit 0 ;;
			*) echo "Unknown option" ;;
		esac
	done
}

menu
