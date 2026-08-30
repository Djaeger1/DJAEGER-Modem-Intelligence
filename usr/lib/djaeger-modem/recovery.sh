#!/bin/sh
# DJAEGER Connectivity Recovery Engine v1.2-rc2
# Goal: restore Internet with the least disruptive verified action first.
RECOVERY_LOG=/root/djaeger-modem/recovery-outcomes.csv
[ -f "$RECOVERY_LOG" ] || echo 'epoch,cause,action,result' > "$RECOVERY_LOG"
recovery_record(){ printf '%s,%s,%s,%s\n' "$(date +%s)" "$1" "$2" "$3" >> "$RECOVERY_LOG"; }
recovery_budget_ok(){
 CD="$(uciopt recovery_cooldown 300)"; MAX="$(uciopt max_recoveries_hour 2)"; N="$(date +%s)"
 [ $((N-LAST_RECOVERY)) -ge "$CD" ] 2>/dev/null || return 1
 if [ "$RECOVERY_WINDOW" -eq 0 ] || [ $((N-RECOVERY_WINDOW)) -ge 3600 ]; then RECOVERY_WINDOW=$N; RECOVERY_COUNT=0; fi
 [ "$RECOVERY_COUNT" -lt "$MAX" ] 2>/dev/null
}
recovery_count_action(){ LAST_RECOVERY="$(date +%s)"; RECOVERY_COUNT=$((RECOVERY_COUNT+1)); }
recover_wan(){
 log "RECOVERY begin action=WAN_RECONNECT cause=$CAUSE"
 if ifup wan >/dev/null 2>&1; then LAST_ACTION=WAN_RECONNECT; recovery_count_action; recovery_record "$CAUSE" WAN_RECONNECT STARTED; CUR=RECOVERING; return 0; fi
 LAST_ACTION=WAN_RECONNECT_FAILED; recovery_count_action; recovery_record "$CAUSE" WAN_RECONNECT FAILED; return 1
}
huawei_post(){
 endpoint="$1"; body="$2"
 [ "$(uciopt allow_modem_post 0)" = 1 ] || return 1
 session || return 1
 curl -fsS --max-time 8 -H "Cookie: $SESSION" -H "__RequestVerificationToken: $TOKEN" -H 'Content-Type: application/xml' --data-binary "$body" "$MODEM_URL/api/$endpoint" >/dev/null 2>&1
}
recover_modem_reboot(){
 [ "$(uciopt allow_modem_reboot 0)" = 1 ] || return 1
 case "$CAUSE" in CELLULAR_SERVICE_LOST|SIM_OR_MODEM_SERVICE|DATA_SESSION_LOST) :;; *) return 1;; esac
 log "RECOVERY escalate action=MODEM_REBOOT cause=$CAUSE"
 if huawei_post device/control '<request><Control>1</Control></request>'; then LAST_ACTION=MODEM_REBOOT; recovery_count_action; recovery_record "$CAUSE" MODEM_REBOOT STARTED; CUR=RECOVERING; return 0; fi
 LAST_ACTION=MODEM_REBOOT_FAILED; recovery_count_action; recovery_record "$CAUSE" MODEM_REBOOT FAILED; return 1
}
recover_connectivity(){
 [ "$(uciopt self_heal 0)" = 1 ] || return 1
 recovery_budget_ok || { log 'RECOVERY_BLOCKED budget_or_cooldown'; return 1; }
 # L1 remains first choice. Modem reboot is optional escalation and is disabled by default.
 [ "$(uciopt allow_wan_reconnect 0)" = 1 ] && recover_wan && return 0
 recover_modem_reboot && return 0
 return 1
}
