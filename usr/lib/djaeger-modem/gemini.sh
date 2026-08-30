#!/bin/sh
# DJAEGER Gemini Advisor v1.2 - advisory only, no shell/action authority.
GEMINI_DIR=/root/djaeger-modem/gemini
GEMINI_KEY=$GEMINI_DIR/api.key
GEMINI_STATE=$GEMINI_DIR/advisor.state
mkdir -p "$GEMINI_DIR"
chmod 700 "$GEMINI_DIR" 2>/dev/null

gemini_enabled(){ [ "$(uciopt gemini_enabled 0)" = 1 ] && [ -s "$GEMINI_KEY" ]; }
gemini_set_key(){ umask 077; cat > "$GEMINI_KEY"; chmod 600 "$GEMINI_KEY"; }
gemini_clear_key(){ rm -f "$GEMINI_KEY"; }
gemini_key_status(){ [ -s "$GEMINI_KEY" ] && echo CONFIGURED || echo NOT_CONFIGURED; }
json_escape(){ printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

gemini_advise(){
 gemini_enabled || return 0
 # Never send subscriber/device identity. Only operational telemetry and local diagnosis.
 MODEL="$(uciopt gemini_model gemini-2.5-flash)"
 TIMEOUT="$(uciopt gemini_timeout 8)"
 KEY="$(cat "$GEMINI_KEY" 2>/dev/null)"; [ -n "$KEY" ] || return 0
 PROMPT="You are DJAEGER Modem Advisor. Analyze operational modem telemetry only. Never request identifiers, credentials, shell commands, firmware changes, APN changes, band locking, IMEI changes, factory reset, or unrestricted actions. Return exactly one compact line: DIAGNOSIS=<category>; CONFIDENCE=<0-100>; ADVICE=<short advisory>. Local safety controller is authoritative. state=$CUR local_cause=$CAUSE local_confidence=$CONF risk=${AI_RISK:-0} rsrp=$RSRP rsrq=$RSRQ sinr=$SINR gateway=$GWOK internet=$INET dns=$DNSOK service=$SERVICE sim=$SIM cell_change=${CELL_CHANGE:-0}."
 EP="https://generativelanguage.googleapis.com/v1beta/models/$MODEL:generateContent"
 BODY="{\"contents\":[{\"parts\":[{\"text\":\"$(json_escape "$PROMPT")\"}]}],\"generationConfig\":{\"temperature\":0.1,\"maxOutputTokens\":96}}"
 RESP="$(wget -qO- --timeout="$TIMEOUT" --header='Content-Type: application/json' --header="x-goog-api-key: $KEY" --post-data="$BODY" "$EP" 2>/dev/null)" || RESP=''
 NOW="$(date +%s)"
 if [ -z "$RESP" ]; then printf 'updated=%s\nstatus=TRANSPORT_ERROR\nadvice=NONE\n' "$NOW" > "$GEMINI_STATE"; return 0; fi
 if echo "$RESP" | grep -q '"error"'; then
   CODE="$(echo "$RESP" | sed -n 's/.*"code"[ ]*:[ ]*\([0-9][0-9]*\).*/\1/p' | head -n1)"
   case "$CODE" in 400) ST=BAD_REQUEST;; 401|403) ST=AUTH_OR_PERMISSION;; 429) ST=RATE_LIMITED;; *) ST=API_ERROR;; esac
   printf 'updated=%s\nstatus=%s\nadvice=NONE\n' "$NOW" "$ST" > "$GEMINI_STATE"; return 0
 fi
 TEXT="$(echo "$RESP" | sed -n 's/.*"text"[ ]*:[ ]*"\([^"]*\)".*/\1/p' | head -n1 | tr '\n\r' '  ' | cut -c1-300)"
 [ -n "$TEXT" ] || TEXT=UNPARSEABLE_RESPONSE
 # Sanitize state file so model output can never become executable shell assignments.
 SAFE="$(printf '%s' "$TEXT" | tr -cd 'A-Za-z0-9 _.,;:=+/%?()[]{}@#-' | cut -c1-300)"
 printf 'updated=%s\nstatus=OK\nadvice=%s\n' "$NOW" "$(printf '%s' "$SAFE" | tr ' ' '_')" > "$GEMINI_STATE"
 return 0
}

gemini_status(){
 echo "Gemini      : $([ "$(uciopt gemini_enabled 0)" = 1 ] && echo ENABLED || echo DISABLED)"
 echo "API Key     : $(gemini_key_status)"
 echo "Model       : $(uciopt gemini_model gemini-2.5-flash)"
 if [ -f "$GEMINI_STATE" ]; then . "$GEMINI_STATE" 2>/dev/null; echo "Advisor     : ${status:-UNKNOWN}"; echo "Last Advice : ${advice:-NONE}"; else echo 'Advisor     : NOT_RUN'; fi
}
