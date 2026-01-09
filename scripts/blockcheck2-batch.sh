#!/bin/sh
set -e

BLOCKCHECK="/opt/zapret2/blockcheck2.sh"
BLOCKCHECK_NOINT="/tmp/z24k-blockcheck2-noint.sh"
SERVICE="/opt/zapret2/init.d/sysv/zapret2"
OUT_DIR="/tmp/z24k-bc2-logs"
RESULTS="/tmp/z24k-blockcheck2-results.txt"
CAT_FILE="/opt/zapret2/z24k-categories.ini"

URLS_DEFAULT="https://www.youtube.com/ https://rr1---sn-jvhnu5g-n8vr.googlevideo.com https://rutracker.org/"

need_cmd() {
	command -v "$1" >/dev/null 2>&1
}

dedupe_urls() {
	awk '
		{
			for (i=1; i<=NF; i++) {
				u=$i
				if (u == "") continue
				if (!(u in seen)) {
					seen[u]=1
					out=out u " "
				}
			}
		}
		END { sub(/[[:space:]]+$/, "", out); print out }
	'
}

url_list_from_categories() {
	[ -f "$CAT_FILE" ] || return 0
	awk -F= '/^test_url=/{print $2}' "$CAT_FILE" | tr -d '\r' | tr '\n' ' '
}

sanitize_name() {
	printf "%s" "$1" | sed 's|https\?://||g; s|[^a-zA-Z0-9._-]|_|g'
}

extract_strategies_all() {
	testname="$1"
	logfile="$2"
	grep -F "working strategy found" "$logfile" | grep -F "$testname" \
		| sed -e 's/^.*: [^ ]* //' -e 's/ !!!!!$//' -e 's/^nfqws2 //' -e 's/^dvtws2 //' -e 's/^winws2 //' \
		| sed 's/[[:space:]]*$//' | sort -u
}

if [ ! -x "$BLOCKCHECK" ]; then
	echo "blockcheck2.sh not found at $BLOCKCHECK"
	exit 1
fi

mkdir -p "$OUT_DIR"
: > "$RESULTS"

if [ -n "$URLS" ]; then
	URLS_ALL="$URLS"
else
	URLS_ALL="$(printf "%s %s" "$URLS_DEFAULT" "$(url_list_from_categories)")"
fi
URLS_ALL="$(printf "%s\n" "$URLS_ALL" | dedupe_urls)"

echo "URLs: $URLS_ALL" | tee -a "$RESULTS"
echo "Results file: $RESULTS"
echo "Logs: $OUT_DIR"

STOP_ZAPRET="${STOP_ZAPRET:-1}"
if [ "$STOP_ZAPRET" = "1" ] && [ -x "$SERVICE" ]; then
	"$SERVICE" stop >/dev/null 2>&1 || true
fi

# use blockcheck2 in batch mode (no prompts)
BLOCKCHECK_NOINT="$BLOCKCHECK"

for url in $URLS_ALL; do
	dom=$(printf "%s" "$url" | sed 's|^https\?://||; s|/.*$||')
	[ -n "$dom" ] || continue
	name=$(sanitize_name "$url")
	for tls in tls12 tls13; do
		logfile="$OUT_DIR/${name}.${tls}.log"
		echo "=== $dom ($tls) ===" | tee -a "$RESULTS"
		if [ "$tls" = "tls12" ]; then
			TLS12=1
			TLS13=0
		else
			TLS12=0
			TLS13=1
		fi
		env BATCH=1 TEST=custom DOMAINS="$dom" ZAPRET_BASE="/opt/zapret2" ZAPRET_RW="/opt/zapret2" \
			SKIP_DNSCHECK=1 ENABLE_HTTP=0 ENABLE_HTTPS_TLS12=$TLS12 ENABLE_HTTPS_TLS13=$TLS13 ENABLE_HTTP3=0 \
			REPEATS=1 SCANLEVEL=force PARALLEL=0 IPVS=4 \
			sh "$BLOCKCHECK_NOINT" >"$logfile" 2>&1 || true
		strats=$(extract_strategies_all "curl_test_https_${tls}" "$logfile")
		if [ -n "$strats" ]; then
			count=$(printf "%s\n" "$strats" | wc -l | tr -d ' ')
			echo "FOUND_COUNT: $count" | tee -a "$RESULTS"
			printf "%s\n" "$strats" | while IFS= read -r s; do
				[ -n "$s" ] && echo "FOUND: $s" | tee -a "$RESULTS"
			done
		else
			echo "FOUND: NONE" | tee -a "$RESULTS"
		fi
		echo "" | tee -a "$RESULTS"
	done
done

if [ "$STOP_ZAPRET" = "1" ] && [ -x "$SERVICE" ]; then
	"$SERVICE" start >/dev/null 2>&1 || true
fi

echo "Done. Results: $RESULTS"
