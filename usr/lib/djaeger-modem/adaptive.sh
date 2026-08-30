#!/bin/sh
# DJAEGER v1.2 Adaptive Intelligence - observer only; never invokes recovery.
ADAPT_DIR=/root/djaeger-modem/adaptive
ADAPT_STATE=$ADAPT_DIR/baseline.state
ADAPT_EVENTS=$ADAPT_DIR/anomalies.csv
mkdir -p "$ADAPT_DIR"
ai_num(){ printf '%s' "$1" | sed 's/[^0-9.-]//g'; }
ai_get(){ sed -n "s/^$1=//p" "$ADAPT_STATE" 2>/dev/null | head -n1; }
ai_int(){ case "$1" in ''|*[!0-9-]*) echo "$2";; *) echo "$1";; esac; }
adaptive_init(){
 [ -f "$ADAPT_EVENTS" ] || echo 'epoch,risk,reason,rsrp_delta,rsrq_delta,sinr_delta,cell_change' > "$ADAPT_EVENTS"
 AI_N="$(ai_int "$(ai_get AI_N)" 0)"; AI_BASE_RSRP="$(ai_int "$(ai_get AI_BASE_RSRP)" 0)"; AI_BASE_RSRQ="$(ai_int "$(ai_get AI_BASE_RSRQ)" 0)"; AI_BASE_SINR="$(ai_int "$(ai_get AI_BASE_SINR)" 0)"; AI_LAST_CELL="$(ai_int "$(ai_get AI_LAST_CELL)" 0)"; AI_RISK="$(ai_int "$(ai_get AI_RISK)" 0)"; AI_STREAK="$(ai_int "$(ai_get AI_STREAK)" 0)"; AI_REASON="$(ai_get AI_REASON)"; [ -n "$AI_REASON" ] || AI_REASON=LEARNING
}
adaptive_save(){
 cat > "$ADAPT_STATE.tmp" <<EOF
AI_N=$AI_N
AI_BASE_RSRP=$AI_BASE_RSRP
AI_BASE_RSRQ=$AI_BASE_RSRQ
AI_BASE_SINR=$AI_BASE_SINR
AI_LAST_CELL=$AI_LAST_CELL
AI_RISK=$AI_RISK
AI_STREAK=$AI_STREAK
AI_REASON=$AI_REASON
EOF
 chmod 600 "$ADAPT_STATE.tmp"; mv "$ADAPT_STATE.tmp" "$ADAPT_STATE"
}
adaptive_observe(){
 AR="$(ai_num "$RSRP")"; AQ="$(ai_num "$RSRQ")"; AS="$(ai_num "$SINR")"
 [ -n "$AR" ] && [ -n "$AQ" ] && [ -n "$AS" ] || return 0
 case "$AR:$AQ:$AS" in *.*) return 0;; esac
 MIN="$(ai_int "$(uciopt baseline_min_samples 40)" 40)"; TH="$(ai_int "$(uciopt anomaly_threshold 60)" 60)"; NEED="$(ai_int "$(uciopt predictive_confirmations 3)" 3)"
 CELL_CHANGE=0; [ "$AI_LAST_CELL" != 0 ] && [ -n "$CELL" ] && [ "$CELL" != "$AI_LAST_CELL" ] && CELL_CHANGE=1
 [ -n "$CELL" ] && case "$CELL" in *[!0-9]*) :;; *) AI_LAST_CELL="$CELL";; esac
 AI_RISK=0; AI_REASON=LEARNING
 if [ "$AI_N" -ge "$MIN" ]; then
   DR=$((AR-AI_BASE_RSRP)); DQ=$((AQ-AI_BASE_RSRQ)); DS=$((AS-AI_BASE_SINR)); AI_REASON=NORMAL
   [ "$DR" -le -12 ] && AI_RISK=$((AI_RISK+30)); [ "$DQ" -le -5 ] && AI_RISK=$((AI_RISK+25)); [ "$DS" -le -8 ] && AI_RISK=$((AI_RISK+30)); [ "$CELL_CHANGE" = 1 ] && AI_RISK=$((AI_RISK+15))
   if [ "$AI_RISK" -ge "$TH" ]; then AI_STREAK=$((AI_STREAK+1)); [ "$AI_STREAK" -ge "$NEED" ] && AI_REASON=RADIO_ANOMALY_CONFIRMED || AI_REASON=RADIO_ANOMALY_PENDING; else AI_STREAK=0; fi
 else DR=0; DQ=0; DS=0; AI_STREAK=0; fi
 # Learn only healthy, non-anomalous samples and only after scoring against the previous baseline.
 if [ "$CUR" = HEALTHY ] && [ "$AI_RISK" -lt "$TH" ]; then
   if [ "$AI_N" -eq 0 ]; then AI_BASE_RSRP=$AR; AI_BASE_RSRQ=$AQ; AI_BASE_SINR=$AS; AI_N=1
   elif [ "$AI_N" -lt 240 ]; then N2=$((AI_N+1)); AI_BASE_RSRP=$(((AI_BASE_RSRP*AI_N+AR)/N2)); AI_BASE_RSRQ=$(((AI_BASE_RSRQ*AI_N+AQ)/N2)); AI_BASE_SINR=$(((AI_BASE_SINR*AI_N+AS)/N2)); AI_N=$N2
   else AI_BASE_RSRP=$(((AI_BASE_RSRP*15+AR)/16)); AI_BASE_RSRQ=$(((AI_BASE_RSRQ*15+AQ)/16)); AI_BASE_SINR=$(((AI_BASE_SINR*15+AS)/16)); fi
 fi
 if [ "$AI_REASON" = RADIO_ANOMALY_CONFIRMED ]; then echo "$(date +%s),$AI_RISK,$AI_REASON,$DR,$DQ,$DS,$CELL_CHANGE" >> "$ADAPT_EVENTS"; L=$(wc -l < "$ADAPT_EVENTS" 2>/dev/null); [ "$L" -gt 1001 ] && { head -n1 "$ADAPT_EVENTS" > "$ADAPT_EVENTS.new"; tail -n 1000 "$ADAPT_EVENTS" >> "$ADAPT_EVENTS.new"; mv "$ADAPT_EVENTS.new" "$ADAPT_EVENTS"; }; fi
 adaptive_save
}
adaptive_status(){ adaptive_init; MIN="$(ai_int "$(uciopt baseline_min_samples 40)" 40)"; echo "Adaptive AI : $([ "$AI_N" -ge "$MIN" ] && echo ACTIVE || echo LEARNING)"; echo "Samples     : $AI_N/$MIN minimum"; echo "Baseline    : RSRP ${AI_BASE_RSRP}dBm | RSRQ ${AI_BASE_RSRQ}dB | SINR ${AI_BASE_SINR}dB"; echo "Risk        : ${AI_RISK}/100"; echo "Streak      : ${AI_STREAK}"; echo "Assessment  : ${AI_REASON}"; }
