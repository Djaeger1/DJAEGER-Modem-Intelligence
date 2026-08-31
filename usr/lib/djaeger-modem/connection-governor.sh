#!/bin/sh
# DJAEGER Adaptive Connection Governor v1
# Conservative local-only shaping. It never changes provider/modem identity or bypasses provider controls.
umask 077
STATE=/root/djaeger-modem/connection-governor.state
HIST=/root/djaeger-modem/connection-pressure.csv
POL=/etc/djaeger-modem/providers/xl.policy
[ -f "$POL" ] || POL=/usr/share/djaeger-modem/providers/xl.policy
mkdir -p /root/djaeger-modem
pget(){ sed -n "s/^$1=//p" "$POL" 2>/dev/null | head -n1; }
[ "$(pget allow_local_traffic_governor)" = 1 ] || exit 0
# Explicitly opt-in at runtime; policy permission alone never silently changes traffic.
[ "$(uci -q get djaeger_modem.main.traffic_governor 2>/dev/null)" = 1 ] || exit 0
command -v tc >/dev/null 2>&1 || exit 0
DEV="$(uci -q get djaeger_modem.main.governor_device 2>/dev/null)"; [ -n "$DEV" ] || DEV=br-lan
ip link show "$DEV" >/dev/null 2>&1 || exit 0
MODE="${1:-observe}"; RATE="${2:-}"
case "$RATE" in ''|*[!0-9]*) [ "$MODE" = relax ] || RATE=0;; esac
# Hard safety envelope: no accidental near-zero denial of service and no absurd values.
MIN="$(uci -q get djaeger_modem.main.governor_min_mbit 2>/dev/null)"; MAX="$(uci -q get djaeger_modem.main.governor_max_mbit 2>/dev/null)"; case "$MIN" in ''|*[!0-9]*) MIN=5;; esac; case "$MAX" in ''|*[!0-9]*) MAX=1000;; esac
apply(){ R="$1"; [ "$R" -ge "$MIN" ] && [ "$R" -le "$MAX" ] || return 1; tc qdisc replace dev "$DEV" root tbf rate "${R}mbit" burst 64kb latency 50ms || return 1; printf 'mode=LIMITED\nrate_mbit=%s\ndevice=%s\nepoch=%s\n' "$R" "$DEV" "$(date +%s)" > "$STATE"; }
relax(){ tc qdisc del dev "$DEV" root >/dev/null 2>&1 || true; printf 'mode=OPEN\nrate_mbit=0\ndevice=%s\nepoch=%s\n' "$DEV" "$(date +%s)" > "$STATE"; }
# A limit requires an evidence token produced by Local AI after repeated correlation; manual invocation without it is rejected.
evidence_ok(){ F=/tmp/djaeger-modem/governor-evidence; [ -f "$F" ] || return 1; E="$(sed -n 's/^epoch=//p' "$F" | head -n1)"; C="$(sed -n 's/^confidence=//p' "$F" | head -n1)"; N="$(date +%s)"; case "$E:$C" in *[!0-9:]*) return 1;; esac; [ $((N-E)) -le 300 ] && [ "$C" -ge 85 ]; }
case "$MODE" in apply) evidence_ok || exit 2; apply "$RATE";; relax) relax;; observe) :;; *) exit 2;; esac
chmod 600 "$STATE" 2>/dev/null || true
