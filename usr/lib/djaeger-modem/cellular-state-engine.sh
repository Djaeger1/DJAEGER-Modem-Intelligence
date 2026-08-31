#!/bin/sh
# DJAEGER Cellular State Engine v1 - Huawei HiLink + provider relationship classifier.
# Read-only: never changes modem state.
umask 077
BASE=/tmp/djaeger-modem
OUT=$BASE/cellular-state
BLACKBOX=/root/djaeger-modem/cellular-blackbox.csv
MODEM="${DJAEGER_MODEM:-192.168.8.1}"
mkdir -p "$BASE" /root/djaeger-modem
xmlv(){ printf '%s' "$1" | sed -n "s:.*<$2>\([^<]*\)</$2>.*:\1:p" | head -n1; }
get_session(){ X="$(wget -qO- -T 2 "http://$MODEM/api/webserver/SesTokInfo" 2>/dev/null)" || return 1; SID="$(xmlv "$X" SesInfo)"; TOK="$(xmlv "$X" TokInfo)"; [ -n "$SID" ] && [ -n "$TOK" ]; }
api(){ get_session || return 1; wget -qO- -T 2 --header="Cookie: $SID" --header="__RequestVerificationToken: $TOK" "http://$MODEM/api/$1" 2>/dev/null; }
probe(){ ping -c1 -W1 1.1.1.1 >/dev/null 2>&1 || ping -c1 -W1 8.8.8.8 >/dev/null 2>&1; }
gw(){ ping -c1 -W1 "$MODEM" >/dev/null 2>&1; }
STATUS="$(api monitoring/status)"; STATUS_OK=0; [ -n "$STATUS" ] && STATUS_OK=1
PLMN="$(api net/current-plmn)"; SIGNAL="$(api device/signal)"
CONN="$(xmlv "$STATUS" ConnectionStatus)"; SERVICE="$(xmlv "$STATUS" ServiceStatus)"; SIM="$(xmlv "$STATUS" SimStatus)"; CELLIP="$(xmlv "$STATUS" WanIPAddress)"
PLMN_NUM="$(xmlv "$PLMN" Numeric)"; PLMN_NAME="$(xmlv "$PLMN" ShortName)"; PSATT="$(xmlv "$SIGNAL" psatt)"; RSRP="$(xmlv "$SIGNAL" rsrp)"; RSRQ="$(xmlv "$SIGNAL" rsrq)"; SINR="$(xmlv "$SIGNAL" sinr)"
gw && GW=UP || GW=DOWN; probe && NET=UP || NET=DOWN
STATE=UNKNOWN; CONF=50
if [ "$GW" = DOWN ]; then STATE=OPENWRT_WAN_OR_MODEM_PATH; CONF=95
elif [ "$STATUS_OK" = 0 ]; then STATE=MODEM_API_UNAVAILABLE; CONF=90
elif [ "$NET" = UP ] && [ -n "$CELLIP" ] && [ "$CELLIP" != 0.0.0.0 ]; then STATE=HEALTHY; CONF=99
elif [ "$SIM" != 1 ]; then STATE=SIM_OR_SERVICE_FAILURE; CONF=95
elif [ -z "$PLMN_NUM" ] || [ "$PLMN_NUM" = 0 ]; then STATE=RADIO_OR_PROVIDER_UNAVAILABLE; CONF=88
elif [ "$PLMN_NUM" = 51011 ] && [ "$PSATT" = 0 ]; then STATE=PLMN_VISIBLE_NOT_REGISTERED; CONF=94
elif [ "$SERVICE" = 2 ] && { [ -z "$CELLIP" ] || [ "$CELLIP" = 0.0.0.0 ]; }; then STATE=REGISTERED_NO_DATA_SESSION; CONF=93
elif [ -n "$CELLIP" ] && [ "$CELLIP" != 0.0.0.0 ] && [ "$NET" = DOWN ]; then STATE=DATA_SESSION_STALLED; CONF=90
elif [ "$PLMN_NUM" = 51011 ] && [ "$NET" = DOWN ]; then STATE=MODEM_PROVIDER; CONF=88
fi
T="$OUT.$$"; printf 'version=1\nepoch=%s\nroot_domain=%s\nconfidence=%s\ngateway=%s\ninternet=%s\napi=%s\nplmn=%s\nprovider=%s\nsim_status=%s\nservice_status=%s\nconnection_status=%s\npacket_attached=%s\ncellular_wan=%s\nrsrp=%s\nrsrq=%s\nsinr=%s\n' "$(date +%s)" "$STATE" "$CONF" "$GW" "$NET" "$STATUS_OK" "${PLMN_NUM:-UNKNOWN}" "${PLMN_NAME:-UNKNOWN}" "${SIM:-UNKNOWN}" "${SERVICE:-UNKNOWN}" "${CONN:-UNKNOWN}" "${PSATT:-UNKNOWN}" "${CELLIP:-NONE}" "${RSRP:-UNKNOWN}" "${RSRQ:-UNKNOWN}" "${SINR:-UNKNOWN}" > "$T" && chmod 600 "$T" && mv "$T" "$OUT"
# Sanitized black box: no IMEI/IMSI/ICCID/serial/MAC/session/token.
[ -f "$BLACKBOX" ] || printf 'epoch,state,confidence,gateway,internet,api,plmn,sim,service,connection,psatt,cellular_wan\n' > "$BLACKBOX"
printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' "$(date +%s)" "$STATE" "$CONF" "$GW" "$NET" "$STATUS_OK" "${PLMN_NUM:-UNKNOWN}" "${SIM:-UNKNOWN}" "${SERVICE:-UNKNOWN}" "${CONN:-UNKNOWN}" "${PSATT:-UNKNOWN}" "${CELLIP:-NONE}" >> "$BLACKBOX"
chmod 600 "$BLACKBOX"; L="$(awk 'END{print NR+0}' "$BLACKBOX")"; [ "$L" -gt 2001 ] && { head -n1 "$BLACKBOX" > "$BLACKBOX.new"; tail -n 2000 "$BLACKBOX" >> "$BLACKBOX.new"; chmod 600 "$BLACKBOX.new"; mv "$BLACKBOX.new" "$BLACKBOX"; }
printf '%s\n' "$STATE"
