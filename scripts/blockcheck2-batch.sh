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

extract_strategy() {
	testname="$1"
	logfile="$2"
	grep -F "working strategy found" "$logfile" | grep -F "$testname" | tail -n1 \
		| sed -e 's/^.*: [^ ]* //' -e 's/ !!!!!$//' -e 's/^nfqws2 //' -e 's/^dvtws2 //' -e 's/^winws2 //' | xargs
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

# create non-interactive wrapper to avoid prompts
if [ -x "$BLOCKCHECK" ]; then
	sed '
		/^BLOCKCHECK_TEST=/d
		/^BLOCKCHECK_ASSUME_YES=/d
		/^BLOCKCHECK_NONINTERACTIVE=/d
	' "$BLOCKCHECK" > "$BLOCKCHECK_NOINT" 2>/dev/null || true
	{
		echo "BLOCKCHECK_TEST=custom"
		echo "BLOCKCHECK_ASSUME_YES=1"
		echo "BLOCKCHECK_NONINTERACTIVE=1"
		cat "$BLOCKCHECK_NOINT"
	} > "$BLOCKCHECK_NOINT.tmp" 2>/dev/null || true
	mv -f "$BLOCKCHECK_NOINT.tmp" "$BLOCKCHECK_NOINT" 2>/dev/null || true
	chmod +x "$BLOCKCHECK_NOINT" 2>/dev/null || true
else
	BLOCKCHECK_NOINT="$BLOCKCHECK"
fi

for url in $URLS_ALL; do
	name=$(sanitize_name "$url")
	for tls in tls12 tls13; do
		logfile="$OUT_DIR/${name}.${tls}.log"
		echo "=== $url ($tls) ===" | tee -a "$RESULTS"
		printf "1\n" | env TEST_URL="$url" TESTS="curl_test_https_${tls}" ZAPRET_BASE="/opt/zapret2" ZAPRET_RW="/opt/zapret2" \
			BLOCKCHECK_TEST=custom BLOCKCHECK_ASSUME_YES=1 BLOCKCHECK_NONINTERACTIVE=1 \
			sh "$BLOCKCHECK_NOINT" >"$logfile" 2>&1 || true
		strat=$(extract_strategy "curl_test_https_${tls}" "$logfile")
		if [ -n "$strat" ]; then
			echo "FOUND: $strat" | tee -a "$RESULTS"
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
