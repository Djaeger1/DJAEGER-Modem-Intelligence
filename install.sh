#!/bin/sh
DJAEGER_INSTALLER_ID=DJAEGER_MODEM_INTELLIGENCE
set -e
[ "$(id -u)" = 0 ] || { echo 'Run as root'; exit 1; }
BASE='https://raw.githubusercontent.com/Djaeger1/DJAEGER-Modem-Intelligence/develop-v1.2-adaptive'
TMP='/tmp/djaeger-v12-candidate'; TS="$(date +%s)"; RB="/root/djaeger-modem/rollback/v1.1-$TS"
echo 'DJAEGER Modem Intelligence v1.2 Adaptive + Gemini Candidate (r2)'
rm -rf "$TMP"; mkdir -p "$TMP/usr/sbin" "$TMP/usr/lib/djaeger-modem" "$TMP/etc/init.d" "$TMP/etc/config"
get(){ wget -qO "$TMP/$2" --timeout=15 "$BASE/$1" || { echo "Download failed: $1"; exit 1; }; }
for F in usr/sbin/djaeger-modem usr/sbin/djaeger-modemd usr/lib/djaeger-modem/common.sh usr/lib/djaeger-modem/adaptive.sh usr/lib/djaeger-modem/gemini.sh etc/init.d/djaeger-modem etc/config/djaeger_modem; do get "$F" "$F"; done
for F in usr/sbin/djaeger-modem usr/sbin/djaeger-modemd usr/lib/djaeger-modem/common.sh usr/lib/djaeger-modem/adaptive.sh usr/lib/djaeger-modem/gemini.sh etc/init.d/djaeger-modem; do sh -n "$TMP/$F" || { echo "Syntax validation failed: $F"; exit 1; }; done
mkdir -p "$RB/usr/sbin" "$RB/usr/lib/djaeger-modem" "$RB/etc/init.d" "$RB/etc/config"
for F in usr/sbin/djaeger-modem usr/sbin/djaeger-modemd usr/lib/djaeger-modem/common.sh etc/init.d/djaeger-modem etc/config/djaeger_modem; do [ -f "/$F" ] && cp -f "/$F" "$RB/$F" || true; done
/etc/init.d/djaeger-modem stop >/dev/null 2>&1 || true
# procd may need several seconds and can SIGKILL a daemon that ignores/doesn't finish TERM.
# Never copy candidate files while an old daemon still owns the singleton lock.
i=0
while [ $i -lt 15 ] && ps w | grep -q '[d]jaeger-modemd'; do sleep 1; i=$((i+1)); done
if ps w | grep -q '[d]jaeger-modemd'; then echo 'Old daemon did not stop safely; candidate installation aborted before file replacement.'; exit 1; fi
# A SIGKILL cannot run the daemon trap, therefore stale mkdir lock must be removed after process death is confirmed.
rm -rf /tmp/djaeger-modem.lock
cp -f "$TMP/usr/sbin/djaeger-modem" /usr/sbin/djaeger-modem; cp -f "$TMP/usr/sbin/djaeger-modemd" /usr/sbin/djaeger-modemd
mkdir -p /usr/lib/djaeger-modem; cp -f "$TMP/usr/lib/djaeger-modem/"*.sh /usr/lib/djaeger-modem/; cp -f "$TMP/etc/init.d/djaeger-modem" /etc/init.d/djaeger-modem
if [ ! -f /etc/config/djaeger_modem ]; then cp -f "$TMP/etc/config/djaeger_modem" /etc/config/djaeger_modem; else
 for KV in "adaptive_intelligence=1" "baseline_min_samples=20" "gemini_enabled=0" "gemini_model=gemini-2.5-flash" "gemini_timeout=8" "gemini_min_interval=900" "gemini_risk_threshold=50"; do K=${KV%%=*}; V=${KV#*=}; uci -q get "djaeger_modem.main.$K" >/dev/null || uci set "djaeger_modem.main.$K=$V"; done
 uci set djaeger_modem.main.allow_modem_post='0'; uci commit djaeger_modem
fi
chmod 755 /usr/sbin/djaeger-modem /usr/sbin/djaeger-modemd /etc/init.d/djaeger-modem; chmod 644 /usr/lib/djaeger-modem/*.sh
/etc/init.d/djaeger-modem enable >/dev/null 2>&1 || true; /etc/init.d/djaeger-modem start
# Require both a live daemon and a fresh state update, not merely procd acceptance.
i=0; START_EPOCH="$(date +%s)"; OK=0
while [ $i -lt 20 ]; do
 if ps w | grep -q '[d]jaeger-modemd' && [ -f /tmp/djaeger-modem/state ]; then
   U="$(sed -n 's/^updated=//p' /tmp/djaeger-modem/state | head -n1)"
   [ -n "$U" ] && [ "$U" -ge "$START_EPOCH" ] 2>/dev/null && { OK=1; break; }
 fi
 sleep 1; i=$((i+1))
done
if [ "$OK" != 1 ]; then
 echo 'Candidate failed runtime health check; restoring v1.1 snapshot.'
 /etc/init.d/djaeger-modem stop >/dev/null 2>&1 || true; sleep 3; rm -rf /tmp/djaeger-modem.lock
 for F in usr/sbin/djaeger-modem usr/sbin/djaeger-modemd usr/lib/djaeger-modem/common.sh etc/init.d/djaeger-modem etc/config/djaeger_modem; do [ -f "$RB/$F" ] && cp -f "$RB/$F" "/$F"; done
 chmod 755 /usr/sbin/djaeger-modem /usr/sbin/djaeger-modemd /etc/init.d/djaeger-modem 2>/dev/null; /etc/init.d/djaeger-modem start; exit 1
fi
rm -rf "$TMP"
echo 'Candidate installed. Adaptive AI enabled; Gemini disabled until API key is configured.'
echo 'Huawei POST/reboot remains hard-locked.'
djaeger-modem status
