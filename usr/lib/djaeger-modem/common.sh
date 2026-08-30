BASE=/tmp/djaeger-modem
PERSIST=/root/djaeger-modem
STATE=$BASE/state
RING=$BASE/telemetry.csv
INCIDENTS=$PERSIST/incidents.csv
LOG=$PERSIST/djaeger-modem.log
mkdir -p "$BASE" "$PERSIST"
log(){ printf '%s %s\n' "$(date '+%F %T')" "$*" >> "$LOG"; }
xmlv(){ echo "$1" | sed -n "s:.*<$2>\([^<]*\)</$2>.*:\1:p" | head -n1; }
num(){ echo "$1" | sed 's/[^0-9.-]//g'; }
uciopt(){ uci -q get "djaeger_modem.main.$1" 2>/dev/null || echo "$2"; }
