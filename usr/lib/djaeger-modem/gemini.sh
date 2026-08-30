#!/bin/sh
# DJAEGER Gemini Advisor v1.2 - advisory only. Never executes model output.
GEMINI_DIR=/root/djaeger-modem/gemini
GEMINI_KEY=$GEMINI_DIR/api.key
GEMINI_STATE=$GEMINI_DIR/advisor.state
mkdir -p "$GEMINI_DIR"; chmod 700 "$GEMINI_DIR" 2>/dev/null

gemini_enabled(){ [ "$(uciopt gemini_enabled 0)" = 1 ] && [ -s "$GEMINI_KEY" ]; }
gemini_set_key(){ umask 077; cat > "$GEMINI_KEY"; chmod 600 "$GEMINI_KEY"; }
gemini_clear_key(){ rm -f "$GEMINI_KEY"; }
gemini_key_status(){ [ -s "$GEMINI_KEY" ] && echo CONFIGURED || echo NOT_CONFIGURED; }
gemini_state_get(){ sed -n "s/^$1=//p" "$GEMINI_STATE" 2>/dev/null | head -n1; }
json_escape(){ printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
gemini_write_state(){ printf 'updated=%s\nstatus=%s\nadvice=%s\n' "$(date +%s)" "$1" "$2" > "$GEMINI_STATE.tmp"; chmod 600 "$GEMINI_STATE.tmp"; mv "$GEMINI_STATE.tmp" "$GEMINI_STATE"; }

gemini_advise(){
 gemini_enabled || return 0
 command -v curl >/dev/null 2>&1 || { gemini_write_state NO_CURL NONE; return 0; }
 command -v jsonfilter >/dev/null 2>&1 || { gemini_write_state NO_JSONFILTER NONE; return 0; }
 MODEL="$(uciopt gemini_model gemini-2.5-flash)"; TIMEOUT="$(uciopt gemini_timeout 8)"
 KEY="$(cat "$GEMINI_KEY" 2>/dev/null)"; [ -n "$KEY" ] || return 0
 PROMPT="You are DJAEGER Modem Advisor. Analyze operational modem telemetry only. Never request identifiers, credentials, shell commands, firmware changes, APN changes, band locking, IMEI changes, factory reset, or unrestricted actions. Return exactly one compact line: DIAGNOSIS=<category>; CONFIDENCE=<0-100>; ADVICE=<short advisory>. Local safety controller is authoritative. state=$CUR local_cause=$CAUSE local_confidence=$CONF risk=${AI_RISK:-0} rsrp=$RSRP rsrq=$RSRQ sinr=$SINR gateway=$GWOK internet=$INET dns=$DNSOK service=$SERVICE sim=$SIM cell_change=${CELL_CHANGE:-0}."
 BODY="{\"contents\":[{\"parts\":[{\"text\":\"$(json_escape "$PROMPT")\"}]}],\"generationConfig\":{\"temperature\":0.1,\"maxOutputTokens\":96}}"
 RESP="$(curl -sS --max-time "$TIMEOUT" -H 'Content-Type: application/json' -H "x-goog-api-key: $KEY" --data-binary "$BODY" "https://generativelanguage.googleapis.com/v1beta/models/$MODEL:generateContent" 2>/dev/null)" || RESP=''
 KEY=''; unset KEY
 [ -n "$RESP" ] || { gemini_write_state TRANSPORT_ERROR NONE; return 0; }
 CODE="$(printf '%s' "$RESP" | jsonfilter -e '@.error.code' 2>/dev/null | head -n1)"
 if [ -n "$CODE" ]; then case "$CODE" in 400) ST=BAD_REQUEST;; 401|403) ST=AUTH_OR_PERMISSION;; 429) ST=RATE_LIMITED;; *) ST=API_ERROR;; esac; gemini_write_state "$ST" NONE; return 0; fi
 TEXT="$(printf '%s' "$RESP" | jsonfilter -e '@.candidates[0].content.parts[0].text' 2>/dev/null | tr '\n\r' '  ' | cut -c1-300)"
 [ -n "$TEXT" ] || { gemini_write_state UNPARSEABLE_RESPONSE NONE; return 0; }
 # Stored as display-only data. Strict charset and never sourced as shell.
 SAFE="$(printf '%s' "$TEXT" | tr -cd 'A-Za-z0-9 _.,:=+/%@#-' | tr ' ' '_' | cut -c1-300)"
 [ -n "$SAFE" ] || SAFE=NONE
 gemini_write_state OK "$SAFE"
}

gemini_status(){
 echo "Gemini      : $([ "$(uciopt gemini_enabled 0)" = 1 ] && echo ENABLED || echo DISABLED)"
 echo "API Key     : $(gemini_key_status)"
 echo "Model       : $(uciopt gemini_model gemini-2.5-flash)"
 if [ -f "$GEMINI_STATE" ]; then
   GS="$(gemini_state_get status)"; GA="$(gemini_state_get advice)"
   echo "Advisor     : ${GS:-UNKNOWN}"; echo "Last Advice : ${GA:-NONE}"
 else echo 'Advisor     : NOT_RUN'; fi
}
