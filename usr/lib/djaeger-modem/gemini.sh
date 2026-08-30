#!/bin/sh
# DJAEGER Gemini Whole-System Advisor. Cloud insight is advisory; local controller remains execution authority.
GEMINI_DIR=/root/djaeger-modem/gemini; GEMINI_KEY=$GEMINI_DIR/api.key; GEMINI_STATE=$GEMINI_DIR/advisor.state; GEMINI_MEMORY=$GEMINI_DIR/insights.csv
mkdir -p "$GEMINI_DIR"; chmod 700 "$GEMINI_DIR" 2>/dev/null
[ -f "$GEMINI_MEMORY" ] || echo 'epoch,state,root_domain,local_risk,system_risk,diagnosis,confidence,advice' > "$GEMINI_MEMORY"
gemini_enabled(){ [ "$(uciopt gemini_enabled 0)" = 1 ] && [ -s "$GEMINI_KEY" ]; }
gemini_set_key(){ umask 077; cat > "$GEMINI_KEY"; chmod 600 "$GEMINI_KEY"; }
gemini_clear_key(){ rm -f "$GEMINI_KEY"; }
gemini_key_status(){ [ -s "$GEMINI_KEY" ] && echo CONFIGURED || echo NOT_CONFIGURED; }
gemini_state_get(){ sed -n "s/^$1=//p" "$GEMINI_STATE" 2>/dev/null | head -n1; }
json_escape(){ printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n\r\t' '   '; }
gemini_write_state(){ printf 'updated=%s\nstatus=%s\nadvice=%s\n' "$(date +%s)" "$1" "$2" > "$GEMINI_STATE.tmp"; chmod 600 "$GEMINI_STATE.tmp"; mv "$GEMINI_STATE.tmp" "$GEMINI_STATE"; }
gemini_history_summary(){
 HGOOD="$(tail -n 300 /root/djaeger-modem/system-health.csv 2>/dev/null | awk -F, '$2==1{n++;l+=$3;c+=$5} END{if(n)printf "healthy_samples=%d avg_load100=%d avg_conntrack_pct=%d",n,l/n,c/n;else print "healthy_samples=0"}')"
 RECENT="$(tail -n 8 /root/djaeger-modem/incidents.csv 2>/dev/null | tr '\n' '|' | cut -c1-700)"
 printf '%s recent_incidents=%s' "$HGOOD" "$RECENT"
}
gemini_advise(){
 gemini_enabled || return 0; command -v curl >/dev/null 2>&1 || { gemini_write_state NO_CURL NONE; return 0; }; command -v jsonfilter >/dev/null 2>&1 || { gemini_write_state NO_JSONFILTER NONE; return 0; }
 MODEL="$(uciopt gemini_model gemini-2.5-flash)"; TIMEOUT="$(uciopt gemini_timeout 8)"; KEY="$(cat "$GEMINI_KEY" 2>/dev/null)"; [ -n "$KEY" ] || return 0
 HIST="$(gemini_history_summary)"
 PROMPT="You are DJAEGER Whole-System Connectivity Advisor. Goal: maximize long-term Internet stability. Learn from BOTH healthy and failed states and compare current telemetry with historical healthy behavior. Analyze cellular radio, Huawei modem/service/data session, OpenWrt WAN, routing, DNS, conntrack/resource pressure, USB/kernel network errors, Internet reachability, local adaptive risk, root-cause correlation and recovery history. Identify likely causal relationships and propose the least disruptive solution. Never request or expose IMEI, IMSI, ICCID, serial, MAC, API keys or credentials. Never output shell commands, arbitrary code, factory reset, IMEI changes or unrestricted root actions. Your output is advisory evidence only; local typed safety controller decides execution. Return exactly: DIAGNOSIS=<category>;CONFIDENCE=<0-100>;ADVICE=<short>;HEALTH_INSIGHT=<what appears to keep this system healthy>. current_state=$CUR root_domain=${ROOT_DOMAIN:-UNKNOWN} root_reason=${ROOT_REASON:-$CAUSE} root_conf=${ROOT_CONF:-$CONF} local_cause=$CAUSE local_risk=${AI_RISK:-0} system_risk=${SYS_RISK:-0} system_reason=${SYS_REASON:-UNKNOWN} modem=$MODEM_OK service=$SERVICE sim=$SIM connection=$CONN rsrp=$RSRP rsrq=$RSRQ sinr=$SINR gateway=$GWOK internet=$INET dns=$DNSOK wan_up=${WAN_UP:-0} route=${ROUTE_OK:-0} dnsmasq=${DNSMASQ_OK:-0} conntrack_pct=${CTPCT:-0} load100=${LOAD100:-0} memavailable_kb=${MEMAVAIL:-0} usb_present=${USB_PRESENT:-0} kernel_net_errors=${KERR:-0}. history=$HIST"
 BODY="{\"contents\":[{\"parts\":[{\"text\":\"$(json_escape "$PROMPT")\"}]}],\"generationConfig\":{\"temperature\":0.1,\"maxOutputTokens\":180}}"
 RESP="$(curl -sS --max-time "$TIMEOUT" -H 'Content-Type: application/json' -H "x-goog-api-key: $KEY" --data-binary "$BODY" "https://generativelanguage.googleapis.com/v1beta/models/$MODEL:generateContent" 2>/dev/null)" || RESP=''; KEY=''; unset KEY
 [ -n "$RESP" ] || { gemini_write_state TRANSPORT_ERROR NONE; return 0; }; CODE="$(printf '%s' "$RESP" | jsonfilter -e '@.error.code' 2>/dev/null | head -n1)"; if [ -n "$CODE" ]; then case "$CODE" in 400) ST=BAD_REQUEST;;401|403) ST=AUTH_OR_PERMISSION;;429) ST=RATE_LIMITED;;*) ST=API_ERROR;;esac; gemini_write_state "$ST" NONE; return 0; fi
 TEXT="$(printf '%s' "$RESP" | jsonfilter -e '@.candidates[0].content.parts[0].text' 2>/dev/null | tr '\n\r' '  ' | cut -c1-700)"; [ -n "$TEXT" ] || { gemini_write_state UNPARSEABLE_RESPONSE NONE; return 0; }
 SAFE="$(printf '%s' "$TEXT" | tr -cd 'A-Za-z0-9 _.,:=+/%@#;()-' | tr ' ' '_' | cut -c1-700)"; [ -n "$SAFE" ] || SAFE=NONE; gemini_write_state OK "$SAFE"
 printf '%s,%s,%s,%s,%s,%s\n' "$(date +%s)" "${CUR:-UNKNOWN}" "${ROOT_DOMAIN:-UNKNOWN}" "${AI_RISK:-0}" "${SYS_RISK:-0}" "$SAFE" >> "$GEMINI_MEMORY"; L="$(wc -l < "$GEMINI_MEMORY" 2>/dev/null)"; [ "${L:-0}" -gt 1001 ] && { head -n1 "$GEMINI_MEMORY" > "$GEMINI_MEMORY.new"; tail -n 1000 "$GEMINI_MEMORY" >> "$GEMINI_MEMORY.new"; mv "$GEMINI_MEMORY.new" "$GEMINI_MEMORY"; }
}
gemini_status(){ echo "Gemini      : $([ "$(uciopt gemini_enabled 0)" = 1 ] && echo ENABLED || echo DISABLED)"; echo "API Key     : $(gemini_key_status)"; echo "Model       : $(uciopt gemini_model gemini-2.5-flash)"; if [ -f "$GEMINI_STATE" ]; then echo "Advisor     : $(gemini_state_get status)"; echo "Last Insight: $(gemini_state_get advice)"; else echo 'Advisor     : NOT_RUN'; fi; }
