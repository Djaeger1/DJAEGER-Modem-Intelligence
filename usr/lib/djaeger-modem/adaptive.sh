#!/bin/sh
# DJAEGER v1.2 Adaptive Intelligence - observer-only engine.
# No recovery action is permitted from this component.
ADAPT_DIR=/root/djaeger-modem/adaptive
ADAPT_STATE=$ADAPT_DIR/baseline.state
ADAPT_EVENTS=$ADAPT_DIR/anomalies.csv
mkdir -p "$ADAPT_DIR"

ai_num(){ echo "$1" | sed 's/[^0-9.-]//g'; }
ai_abs(){ [ "$1" -lt 0 ] 2>/dev/null && echo $((0-$1)) || echo "$1"; }

adaptive_init(){
 [ -f "$ADAPT_EVENTS" ] || echo 'epoch,risk,reason,rsrp_delta,rsrq_delta,sinr_delta,cell_change' > "$ADAPT_EVENTS"
 AI_N=0; AI_RSRP_SUM=0; AI_RSRQ_SUM=0; AI_SINR_SUM=0; AI_BASE_RSRP=0; AI_BASE_RSRQ=0; AI_BASE_SINR=0; AI_LAST_CELL=''; AI_RISK=0; AI_REASON=LEARNING
 if [ -f "$ADAPT_STATE" ]; then . "$ADAPT_STATE" 2>/dev/null || true; fi
}

adaptive_save(){
 cat > "$ADAPT_STATE.tmp" <<EOF
AI_N=$AI_N
AI_RSRP_SUM=$AI_RSRP_SUM
AI_RSRQ_SUM=$AI_RSRQ_SUM
AI_SINR_SUM=$AI_SINR_SUM
AI_BASE_RSRP=$AI_BASE_RSRP
AI_BASE_RSRQ=$AI_BASE_RSRQ
AI_BASE_SINR=$AI_BASE_SINR
AI_LAST_CELL=$AI_LAST_CELL
AI_RISK=$AI_RISK
AI_REASON=$AI_REASON
EOF
 mv "$ADAPT_STATE.tmp" "$ADAPT_STATE"
}

adaptive_observe(){
 # Learn only from samples already proven healthy by deterministic core.
 [ "$CUR" = HEALTHY ] || return 0
 AR="$(ai_num "$RSRP")"; AQ="$(ai_num "$RSRQ")"; AS="$(ai_num "$SINR")"
 [ -n "$AR" ] && [ -n "$AQ" ] && [ -n "$AS" ] || return 0
 # Huawei values are integral on the validated target modem. Ignore malformed values.
 case "$AR:$AQ:$AS" in *.*) return 0;; esac
 AI_N=$((AI_N+1)); AI_RSRP_SUM=$((AI_RSRP_SUM+AR)); AI_RSRQ_SUM=$((AI_RSRQ_SUM+AQ)); AI_SINR_SUM=$((AI_SINR_SUM+AS))
 # Bound learning memory to 240 healthy samples; then use a conservative EWMA-like update.
 if [ "$AI_N" -le 240 ]; then
   AI_BASE_RSRP=$((AI_RSRP_SUM/AI_N)); AI_BASE_RSRQ=$((AI_RSRQ_SUM/AI_N)); AI_BASE_SINR=$((AI_SINR_SUM/AI_N))
 else
   AI_N=240; AI_RSRP_SUM=$((AI_BASE_RSRP*240)); AI_RSRQ_SUM=$((AI_BASE_RSRQ*240)); AI_SINR_SUM=$((AI_BASE_SINR*240))
   AI_BASE_RSRP=$(((AI_BASE_RSRP*15+AR)/16)); AI_BASE_RSRQ=$(((AI_BASE_RSRQ*15+AQ)/16)); AI_BASE_SINR=$(((AI_BASE_SINR*15+AS)/16))
 fi
 AI_RISK=0; AI_REASON=NORMAL
 DR=$((AR-AI_BASE_RSRP)); DQ=$((AQ-AI_BASE_RSRQ)); DS=$((AS-AI_BASE_SINR)); CELL_CHANGE=0
 [ -n "$AI_LAST_CELL" ] && [ -n "$CELL" ] && [ "$CELL" != "$AI_LAST_CELL" ] && CELL_CHANGE=1
 [ -n "$CELL" ] && AI_LAST_CELL="$CELL"
 # Do not declare predictive risk until a minimum baseline exists (~5 minutes at 15s interval).
 if [ "$AI_N" -ge 20 ]; then
   [ "$DR" -le -12 ] && AI_RISK=$((AI_RISK+30))
   [ "$DQ" -le -5 ] && AI_RISK=$((AI_RISK+25))
   [ "$DS" -le -8 ] && AI_RISK=$((AI_RISK+30))
   [ "$CELL_CHANGE" = 1 ] && AI_RISK=$((AI_RISK+15))
   [ "$AI_RISK" -ge 50 ] && AI_REASON=RADIO_ANOMALY
 fi
 if [ "$AI_RISK" -ge 50 ]; then
   echo "$(date +%s),$AI_RISK,$AI_REASON,$DR,$DQ,$DS,$CELL_CHANGE" >> "$ADAPT_EVENTS"
   # Observer only: expose risk, never mutate CUR and never invoke recovery.
 fi
 adaptive_save
}

adaptive_status(){
 adaptive_init
 echo "Adaptive AI : $([ "$AI_N" -ge 20 ] && echo ACTIVE || echo LEARNING)"
 echo "Samples     : $AI_N/20 minimum"
 echo "Baseline    : RSRP ${AI_BASE_RSRP}dBm | RSRQ ${AI_BASE_RSRQ}dB | SINR ${AI_BASE_SINR}dB"
 echo "Risk        : ${AI_RISK}/100"
 echo "Assessment  : ${AI_REASON}"
}
