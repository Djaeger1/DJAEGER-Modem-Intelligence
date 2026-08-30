#!/bin/sh
# DJAEGER Local AI Policy Authority v2. Gemini may propose; Local AI validates and owns policy.
POLICY=/tmp/djaeger-local-ai.policy
AI=/tmp/djaeger-modem/state
OUT=/root/djaeger-modem/watchdog-outcomes.csv
LEARNED=/root/djaeger-modem/local-ai-learned.policy
umask 077
valid_action(){ case "$1" in WAN_RECONNECT|DNSMASQ_RESTART|NETIFD_RESTART|MODEM_REBOOT) return 0;; *) return 1;; esac; }
valid_domain(){ case "$1" in OPENWRT_DNS|DNS_UPSTREAM|OPENWRT_SYSTEM|OPENWRT_WAN|OPENWRT_ROUTING|UPSTREAM|CELLULAR|MODEM|MODEM_DATA_SESSION|MULTI_FACTOR|UNKNOWN|HEALTHY) return 0;; *) return 1;; esac; }
get_domain(){ sed -n 's/^root_domain=//p' "$AI" 2>/dev/null | head -n1; }
learned_get(){ sed -n "s/^$1=//p" "$LEARNED" 2>/dev/null | head -n1; }
defaults(){ case "$1" in OPENWRT_DNS|DNS_UPSTREAM) A1=DNSMASQ_RESTART; A2=WAN_RECONNECT; A3=NETIFD_RESTART;; OPENWRT_SYSTEM) A1=NETIFD_RESTART; A2=WAN_RECONNECT; A3=MODEM_REBOOT;; CELLULAR|MODEM|MODEM_DATA_SESSION|MULTI_FACTOR) A1=WAN_RECONNECT; A2=MODEM_REBOOT; A3=NETIFD_RESTART;; *) A1=WAN_RECONNECT; A2=NETIFD_RESTART; A3=MODEM_REBOOT;; esac; V1=2; V2=4; SOURCE=DETERMINISTIC; }
compile(){ D="$(get_domain)"; [ -n "$D" ] || D=UNKNOWN; valid_domain "$D" || D=UNKNOWN; defaults "$D"; LD="$(learned_get domain)"; if [ "$LD" = "$D" ]; then L1="$(learned_get action1)"; L2="$(learned_get action2)"; L3="$(learned_get action3)"; C="$(learned_get confidence)"; case "$C" in ''|*[!0-9]*) C=0;; esac; if [ "$C" -ge 80 ] && valid_action "$L1" && valid_action "$L2" && valid_action "$L3" && [ "$L1" != MODEM_REBOOT ]; then A1="$L1"; A2="$L2"; A3="$L3"; SOURCE=GEMINI_VALIDATED; fi; fi; T="$POLICY.$$"; printf 'version=2\ngenerated=%s\ndomain=%s\nsource=%s\naction1=%s\naction2=%s\naction3=%s\nverify1=%s\nverify2=%s\n' "$(date +%s)" "$D" "$SOURCE" "$A1" "$A2" "$A3" "$V1" "$V2" > "$T" && chmod 600 "$T" && mv "$T" "$POLICY"; }
propose(){ D="$2"; A1="$3"; A2="$4"; A3="$5"; C="$6"; valid_domain "$D" || return 1; valid_action "$A1" && valid_action "$A2" && valid_action "$A3" || return 1; [ "$A1" != MODEM_REBOOT ] || return 1; case "$C" in ''|*[!0-9]*) return 1;; esac; [ "$C" -ge 80 ] && [ "$C" -le 100 ] || return 1; T="$LEARNED.$$"; printf 'version=1\nupdated=%s\nsource=GEMINI_VALIDATED\ndomain=%s\naction1=%s\naction2=%s\naction3=%s\nconfidence=%s\n' "$(date +%s)" "$D" "$A1" "$A2" "$A3" "$C" > "$T" && chmod 600 "$T" && mv "$T" "$LEARNED"; }
record(){ mkdir -p /root/djaeger-modem; [ -f "$OUT" ] || printf 'epoch,domain,action,result,recovery_ms\n' > "$OUT"; printf '%s,%s,%s,%s,%s\n' "$(date +%s)" "$2" "$3" "$4" "$5" >> "$OUT"; chmod 600 "$OUT"; tail -n 1000 "$OUT" > "$OUT.tmp" && chmod 600 "$OUT.tmp" && mv "$OUT.tmp" "$OUT"; }
case "$1" in compile|'') compile;; propose) propose "$@";; record) shift; record x "$@";; *) exit 2;; esac
