#!/bin/sh
# DJAEGER Adaptive Connection Governor v2 - evidence producer + reversible local shaping.
umask 077
BASE=/tmp/djaeger-modem; STATE=/root/djaeger-modem/connection-governor.state; HIST=/root/djaeger-modem/connection-pressure.csv; EVID=$BASE/governor-evidence; CELL=$BASE/cellular-state
POL=/etc/djaeger-modem/providers/xl.policy; [ -f "$POL" ]||POL=/usr/share/djaeger-modem/providers/xl.policy; mkdir -p "$BASE" /root/djaeger-modem
pget(){ sed -n "s/^$1=//p" "$POL" 2>/dev/null|head -n1; }; cv(){ sed -n "s/^$1=//p" "$CELL" 2>/dev/null|head -n1; }
[ "$(pget allow_local_traffic_governor)" = 1 ]||exit 0; [ "$(uci -q get djaeger_modem.main.traffic_governor 2>/dev/null)" = 1 ]||exit 0; command -v tc >/dev/null 2>&1||exit 0
DEV="$(uci -q get djaeger_modem.main.governor_device 2>/dev/null)";[ -n "$DEV" ]||DEV=br-lan; ip link show "$DEV" >/dev/null 2>&1||exit 0
MODE="${1:-observe}"; RATE="${2:-}"; MIN="$(uci -q get djaeger_modem.main.governor_min_mbit 2>/dev/null)";MAX="$(uci -q get djaeger_modem.main.governor_max_mbit 2>/dev/null)";case "$MIN" in ''|*[!0-9]*)MIN=5;;esac;case "$MAX" in ''|*[!0-9]*)MAX=1000;;esac
sample(){ NOW="$(date +%s)"; DOMAIN="$(cv root_domain)"; NET="$(cv internet)"; RSRP="$(cv rsrp|sed 's/[^0-9-].*//')"; # Lightweight pressure evidence: 5 pings, no traffic generation.
 O="$(ping -c5 -W1 1.1.1.1 2>/dev/null)"; LOSS="$(printf '%s\n' "$O"|sed -n 's/.* \([0-9][0-9]*\)% packet loss.*/\1/p'|tail -n1)"; AVG="$(printf '%s\n' "$O"|awk -F'=' '/min\/avg\/max/{split($2,a,"/");gsub(/ /,"",a[2]);print int(a[2])}')";case "$LOSS" in ''|*[!0-9]*)LOSS=100;;esac;case "$AVG" in ''|*[!0-9]*)AVG=999;;esac; [ -f "$HIST" ]||echo 'epoch,domain,loss_pct,avg_ms' >"$HIST"; printf '%s,%s,%s,%s\n' "$NOW" "${DOMAIN:-UNKNOWN}" "$LOSS" "$AVG" >>"$HIST"; tail -n 31 "$HIST" >"$HIST.tmp"&&mv "$HIST.tmp" "$HIST"; chmod 600 "$HIST";
 # Require 3 recent degraded samples while cellular remains attached/data-capable; outages never create shaping authority.
 C="$(tail -n 5 "$HIST"|awk -F, -v n="$NOW" '$1>=n-600 && $2=="DATA_SESSION_STALLED" && ($3>=20||$4>=180){c++}END{print c+0}')"; if [ "$C" -ge 3 ]; then printf 'epoch=%s\nconfidence=85\nreason=repeated_data_session_pressure\nsamples=%s\n' "$NOW" "$C" >"$EVID";chmod 600 "$EVID"; else rm -f "$EVID"; fi; }
evidence_ok(){ [ -f "$EVID" ]||return 1;E="$(sed -n 's/^epoch=//p' "$EVID"|head -n1)";C="$(sed -n 's/^confidence=//p' "$EVID"|head -n1)";N="$(date +%s)";case "$E:$C" in *[!0-9:]*)return 1;;esac;[ $((N-E)) -le 300 ]&&[ "$C" -ge 85 ]; }
apply(){ R="$1";case "$R" in ''|*[!0-9]*)return 1;;esac;[ "$R" -ge "$MIN" ]&&[ "$R" -le "$MAX" ]||return 1; evidence_ok||return 1; tc qdisc replace dev "$DEV" root tbf rate "${R}mbit" burst 64kb latency 50ms||return 1;printf 'mode=LIMITED\nrate_mbit=%s\ndevice=%s\nepoch=%s\n' "$R" "$DEV" "$(date +%s)" >"$STATE"; }
relax(){ tc qdisc del dev "$DEV" root >/dev/null 2>&1||true;rm -f "$EVID";printf 'mode=OPEN\nrate_mbit=0\ndevice=%s\nepoch=%s\n' "$DEV" "$(date +%s)" >"$STATE"; }
case "$MODE" in observe) sample;;apply) apply "$RATE";;relax) relax;;*)exit 2;;esac;chmod 600 "$STATE" 2>/dev/null||true
