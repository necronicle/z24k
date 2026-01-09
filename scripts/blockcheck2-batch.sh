#!/bin/sh
set -e

BLOCKCHECK="/opt/zapret2/blockcheck2.sh"
BLOCKCHECK_NOINT="/tmp/z24k-blockcheck2-noint.sh"
SERVICE="/opt/zapret2/init.d/sysv/zapret2"
OUT_DIR="/tmp/z24k-bc2-logs"
SUMMARY_TLS12="/opt/zapret2/blockcheck2_summary_tls12.txt"
SUMMARY_TLS13="/opt/zapret2/blockcheck2_summary_tls13.txt"
LOG_BASE="/tmp/z24k-blockcheck2"
CAT_FILE="/opt/zapret2/z24k-categories.ini"

URLS_DEFAULT="https://www.youtube.com/ https://rr1---sn-jvhnu5g-n8vr.googlevideo.com https://rutracker.org/"

if [ ! -x "$BLOCKCHECK" ]; then
	echo "blockcheck2.sh not found at $BLOCKCHECK"
	exit 1
fi

mkdir -p "$OUT_DIR"
: > "$RESULTS"

STOP_ZAPRET="${STOP_ZAPRET:-1}"
if [ "$STOP_ZAPRET" = "1" ] && [ -x "$SERVICE" ]; then
	"$SERVICE" stop >/dev/null 2>&1 || true
fi

run_blockcheck_summary() {
	local label="$1"
	local enable_tls12="$2"
	local enable_tls13="$3"
	local log_file="$LOG_BASE_${label}.log"
	local summary_file="$LOG_BASE_${label}.summary"
	local summary_public="$4"

	env BATCH=1 TEST=standard DOMAINS="$URLS_DEFAULT" ZAPRET_BASE=/opt/zapret2 ZAPRET_RW=/opt/zapret2 \
		SKIP_DNSCHECK=1 ENABLE_HTTP=0 ENABLE_HTTPS_TLS12="$enable_tls12" ENABLE_HTTPS_TLS13="$enable_tls13" ENABLE_HTTP3=0 \
		REPEATS=1 SCANLEVEL=standard PARALLEL=0 IPVS=4 \
		"$BLOCKCHECK" >"$log_file" 2>&1 || true

	awk '
		/^\* SUMMARY/ {in_summary=1}
		in_summary {
			if (/^\* COMMON/ || /^Please note this SUMMARY/ || /^Understanding how strategies work/) exit
			print
		}
	' "$log_file" > "$summary_file"

	if [ -s "$summary_file" ]; then
		cp "$summary_file" "$summary_public"
		echo "SUMMARY (${label}) saved to: $summary_public"
	else
		echo "SUMMARY (${label}) is empty. Log: $log_file"
	fi
}

run_blockcheck_summary "tls12" 1 0 "$SUMMARY_TLS12"
run_blockcheck_summary "tls13" 0 1 "$SUMMARY_TLS13"

if [ "$STOP_ZAPRET" = "1" ] && [ -x "$SERVICE" ]; then
	"$SERVICE" start >/dev/null 2>&1 || true
fi

echo "Done. TLS12: $SUMMARY_TLS12 | TLS13: $SUMMARY_TLS13"
