#!/bin/sh
# DJAEGER Local AI Policy Authority. Compiles trusted local recovery policy.
POLICY=/tmp/djaeger-local-ai.policy
AI=/tmp/djaeger-modem/state
OUT=/root/djaeger-modem/watchdog-outcomes.csv
umask 077
valid_action(){ case "$1" in WAN_RECONNECT|DNSMASQ_RESTART|NETIFD_RESTART|MODEM_REBOOT) return 0;; *) return 1;; esac; }
get_domain(){ sed -n 's/^root_domain=//p' "$AI" 2>/dev/null | head -n1; }
compile(){
 D="$(get_domain)"; [ -n "$D" ] || D=UNKNOWN
 case "$D" in
  OPENWRT_DNS|DNS_UPSTREAM) A1=DNSMASQ_RESTART; A2=WAN_RECONNECT; A3=NETIFD_RESTART;;
  OPENWRT_SYSTEM) A1=NETIFD_RESTART; A2=WAN_RECONNECT; A3=MODEM_REBOOT;;
  CELLULAR|MODEM|MODEM_DATA_SESSION|MULTI_FACTOR) A1=WAN_RECONNECT; A2=MODEM_REBOOT; A3=NETIFD_RESTART;;
  *) A1=WAN_RECONNECT; A2=NETIFD_RESTART; A3=MODEM_REBOOT;;
 esac
 for A in "$A1" "$A2" "$A3"; do valid_action "$A" || exit 1; done
 T="$POLICY.$$"; printf 'version=1\ngenerated=%s\ndomain=%s\naction1=%s\naction2=%s\naction3=%s\nverify1=2\nverify2=4\n' "$(date +%s)" "$D" "$A1" "$A2" "$A3" > "$T" && chmod 600 "$T" && mv "$T" "$POLICY"
}
record(){
 mkdir -p /root/djaeger-modem; [ -f "$OUT" ] || printf 'epoch,domain,action,result,recovery_ms\n' > "$OUT"
 printf '%s,%s,%s,%s,%s\n' "$(date +%s)" "$2" "$3" "$4" "$5" >> "$OUT"; chmod 600 "$OUT"; tail -n 1000 "$OUT" > "$OUT.tmp" && mv "$OUT.tmp" "$OUT"
}
case "$1" in compile|'') compile;; record) shift; record x "$@";; *) exit 2;; esac
