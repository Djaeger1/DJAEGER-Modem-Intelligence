#!/bin/sh
# DJAEGER Modem Monitor Bridge v1.0
# Publishes a strict read-only, redacted snapshot for the LAN Android monitor.
set -eu
STATE=/tmp/djaeger-modem/state
OUT=/www/djaeger-modem/status
TMP="${OUT}.tmp"

safe(){
  key="$1"; def="${2:-UNKNOWN}"
  v="$(sed -n "s/^${key}=//p" "$STATE" 2>/dev/null | head -n1 || true)"
  [ -n "$v" ] || v="$def"
  # Single-line allowlisted text only. Never expose arbitrary state contents.
  printf '%s' "$v" | tr '\r\n' '  ' | sed 's/[^A-Za-z0-9._:+\/-]/_/g' | cut -c1-160
}

mkdir -p /www/djaeger-modem
if [ ! -r "$STATE" ]; then
  printf '%s\n' 'version=1' 'updated=0' 'state=STARTING' 'score=0' 'cause=STATE_UNAVAILABLE' 'root_domain=UNKNOWN' 'root_reason=STATE_UNAVAILABLE' 'root_confidence=0' > "$TMP"
else
  {
    echo 'version=1'
    for k in updated state score cause confidence root_domain root_reason root_confidence system_risk system_reason modem service sim connection wan_ip rsrp rsrq rssi sinr pci gateway internet dns self_heal last_action recovery_count recovery_stage incident_start adaptive_samples adaptive_risk adaptive_reason ai_authority ai_decision_source ai_decision_action ai_decision_confidence; do
      printf '%s=%s\n' "$k" "$(safe "$k")"
    done
  } > "$TMP"
fi
chmod 644 "$TMP"
mv "$TMP" "$OUT"
