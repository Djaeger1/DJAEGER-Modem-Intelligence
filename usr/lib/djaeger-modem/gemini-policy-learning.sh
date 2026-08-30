#!/bin/sh
# Post-recovery learning bridge. Never called from outage critical path.
umask 077
. /usr/lib/djaeger-modem/common.sh
. /usr/lib/djaeger-modem/gemini.sh
LOCALAI=/usr/lib/djaeger-modem/local-ai-policy.sh
OUT=/root/djaeger-modem/watchdog-outcomes.csv
STATE=/tmp/djaeger-fast-watchdog.state
LAST=/root/djaeger-modem/gemini-policy.last
sget(){ sed -n "s/^$1=//p" "$STATE" 2>/dev/null | head -n1; }
online(){ ping -c1 -W2 1.1.1.1 >/dev/null 2>&1 || ping -c1 -W2 8.8.8.8 >/dev/null 2>&1; }
run(){ [ "$(sget state)" = STANDBY ] || return 0; online || return 0; gemini_enabled || return 0; [ -s "$OUT" ] || return 0; LINE="$(tail -n1 "$OUT")"; EPOCH="$(printf '%s' "$LINE" | cut -d, -f1)"; PREV="$(cat "$LAST" 2>/dev/null)"; [ "$EPOCH" != "$PREV" ] || return 0; DOMAIN="$(printf '%s' "$LINE" | cut -d, -f2)"; ACTION="$(printf '%s' "$LINE" | cut -d, -f3)"; RESULT="$(printf '%s' "$LINE" | cut -d, -f4)"; MS="$(printf '%s' "$LINE" | cut -d, -f5)"; # Gemini advisor is used for analysis; only its typed action may become a candidate.
 CUR=HEALTHY; ROOT_DOMAIN="$DOMAIN"; ROOT_REASON=POST_RECOVERY; INCIDENT_START="$EPOCH"; gemini_advise >/dev/null 2>&1 || true
 [ "$(gemini_state_get status)" = OK ] || return 0; ADV="$(gemini_state_get advice)"; GA="$(printf '%s' "$ADV" | tr ';' '\n' | sed -n 's/^ACTION=//p' | head -n1)"; GC="$(printf '%s' "$ADV" | tr ';' '\n' | sed -n 's/^ACTION_CONFIDENCE=//p' | head -n1)"; case "$GA" in WAN_RECONNECT|DNSMASQ_RESTART|NETIFD_RESTART|MODEM_REBOOT) :;; *) GA=NONE;; esac; case "$GC" in ''|*[!0-9]*) GC=0;; esac
 # Conservative compiler: Gemini can reorder a typed sequence, never create commands. Modem reboot can never be first.
 case "$GA" in DNSMASQ_RESTART) A1=DNSMASQ_RESTART; A2=WAN_RECONNECT; A3=NETIFD_RESTART;; NETIFD_RESTART) A1=NETIFD_RESTART; A2=WAN_RECONNECT; A3=MODEM_REBOOT;; MODEM_REBOOT) A1=WAN_RECONNECT; A2=MODEM_REBOOT; A3=NETIFD_RESTART;; WAN_RECONNECT) A1=WAN_RECONNECT; A2=NETIFD_RESTART; A3=MODEM_REBOOT;; *) printf '%s' "$EPOCH" > "$LAST"; return 0;; esac
 "$LOCALAI" propose "$DOMAIN" "$A1" "$A2" "$A3" "$GC" >/dev/null 2>&1 || true; printf '%s' "$EPOCH" > "$LAST"; chmod 600 "$LAST"; logger -t djaeger-gemini-policy "post-recovery analyzed domain=$DOMAIN prior=$ACTION result=$RESULT recovery_ms=$MS candidate=$GA confidence=$GC"; }
run
