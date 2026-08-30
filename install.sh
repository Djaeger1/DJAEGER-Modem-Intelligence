#!/bin/sh
DJAEGER_INSTALLER_ID=DJAEGER_MODEM_INTELLIGENCE
set -e
[ "$(id -u)" = 0 ] || { echo 'Run as root'; exit 1; }
BASE='https://raw.githubusercontent.com/Djaeger1/DJAEGER-Modem-Intelligence/main'
TMP='/tmp/djaeger-v12-rc2'; TS="$(date +%s)"; RB="/root/djaeger-modem/rollback/pre-v12rc2-$TS"
echo 'DJAEGER Modem Intelligence v1.2-rc2 Stability + Staged Recovery'
rm -rf "$TMP"; mkdir -p "$TMP/usr/sbin" "$TMP/usr/lib/djaeger-modem" "$TMP/etc/init.d" "$TMP/etc/config"
get(){ wget -qO "$TMP/$2" --timeout=15 "$BASE/$1" || { echo "Download failed: $1"; exit 1; }; }
FILES='usr/sbin/djaeger-modem usr/sbin/djaeger-modemd usr/lib/djaeger-modem/common.sh usr/lib/djaeger-modem/adaptive.sh usr/lib/djaeger-modem/gemini.sh usr/lib/djaeger-modem/recovery.sh etc/init.d/djaeger-modem etc/config/djaeger_modem'
for F in $FILES; do get "$F" "$F"; done
for F in usr/sbin/djaeger-modem usr/sbin/djaeger-modemd usr/lib/djaeger-modem/common.sh usr/lib/djaeger-modem/adaptive.sh usr/lib/djaeger-modem/gemini.sh usr/lib/djaeger-modem/recovery.sh etc/init.d/djaeger-modem; do sh -n "$TMP/$F" || { echo "Syntax validation failed: $F"; exit 1; }; done
command -v curl >/dev/null 2>&1 || { echo 'Missing dependency: curl'; exit 1; }; command -v jsonfilter >/dev/null 2>&1 || { echo 'Missing dependency: jsonfilter'; exit 1; }
mkdir -p "$RB/usr/sbin" "$RB/usr/lib/djaeger-modem" "$RB/etc/init.d" "$RB/etc/config"
for F in $FILES; do [ -f "/$F" ] && { mkdir -p "$RB/$(dirname "$F")"; cp -f "/$F" "$RB/$F"; } || true; done
/etc/init.d/djaeger-modem stop >/dev/null 2>&1 || true
i=0; while [ $i -lt 20 ] && ps w | grep -q '[d]jaeger-modemd'; do sleep 1; i=$((i+1)); done
ps w | grep -q '[d]jaeger-modemd' && { echo 'Old daemon did not stop safely; installation aborted without replacement.'; exit 1; }
rm -rf /tmp/djaeger-modem.lock
cp -f "$TMP/usr/sbin/djaeger-modem" /usr/sbin/; cp -f "$TMP/usr/sbin/djaeger-modemd" /usr/sbin/; mkdir -p /usr/lib/djaeger-modem; cp -f "$TMP/usr/lib/djaeger-modem/"*.sh /usr/lib/djaeger-modem/; cp -f "$TMP/etc/init.d/djaeger-modem" /etc/init.d/djaeger-modem
if [ ! -f /etc/config/djaeger_modem ]; then cp -f "$TMP/etc/config/djaeger_modem" /etc/config/djaeger_modem; else
 for KV in 'adaptive_intelligence=1' 'baseline_min_samples=40' 'anomaly_threshold=60' 'predictive_confirmations=3' 'gemini_enabled=0' 'gemini_model=gemini-2.5-flash' 'gemini_timeout=8' 'gemini_min_interval=900' 'gemini_risk_threshold=50' 'allow_modem_post=0' 'allow_modem_reboot=0' 'recovery_verify_wait=75'; do K=${KV%%=*}; V=${KV#*=}; uci -q get "djaeger_modem.main.$K" >/dev/null || uci set "djaeger_modem.main.$K=$V"; done
 [ "$(uci -q get djaeger_modem.main.baseline_min_samples)" = 20 ] && uci set djaeger_modem.main.baseline_min_samples='40'; uci set djaeger_modem.main.allow_modem_post='0'; uci set djaeger_modem.main.allow_modem_reboot='0'; uci commit djaeger_modem
fi
chmod 755 /usr/sbin/djaeger-modem /usr/sbin/djaeger-modemd /etc/init.d/djaeger-modem; chmod 644 /usr/lib/djaeger-modem/*.sh; /etc/init.d/djaeger-modem enable >/dev/null 2>&1 || true
rm -f /tmp/djaeger-modem/state; START_EPOCH="$(date +%s)"; /etc/init.d/djaeger-modem start
i=0; OK=0; while [ $i -lt 35 ]; do if ps w | grep -q '[d]jaeger-modemd' && [ -f /tmp/djaeger-modem/state ]; then U="$(sed -n 's/^updated=//p' /tmp/djaeger-modem/state | head -n1)"; [ -n "$U" ] && [ "$U" -ge "$START_EPOCH" ] 2>/dev/null && { OK=1; break; }; fi; sleep 1; i=$((i+1)); done
if [ "$OK" != 1 ]; then echo 'Runtime health check failed; restoring previous installation.'; /etc/init.d/djaeger-modem stop >/dev/null 2>&1 || true; sleep 2; rm -rf /tmp/djaeger-modem.lock; for F in $FILES; do [ -f "$RB/$F" ] && cp -f "$RB/$F" "/$F" || true; done; /etc/init.d/djaeger-modem start >/dev/null 2>&1 || true; echo "Rollback: $RB"; exit 1; fi
rm -rf "$TMP"; echo 'v1.2-rc2 installed and runtime-verified.'; echo 'Staged recovery active. Modem POST/reboot remains LOCKED for safe observation.'; djaeger-modem status
