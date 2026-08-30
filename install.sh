#!/bin/sh
DJAEGER_INSTALLER_ID=DJAEGER_MODEM_INTELLIGENCE
set -e
[ "$(id -u)" = 0 ] || { echo 'Run as root'; exit 1; }
BASE='https://raw.githubusercontent.com/Djaeger1/DJAEGER-Modem-Intelligence/main'
TMP='/tmp/djaeger-modem-command-install'; RB='/root/djaeger-modem/rollback'
echo 'DJAEGER Modem Intelligence v1.1 Command Edition (r2)'
rm -rf "$TMP"; mkdir -p "$TMP/usr/sbin" "$TMP/usr/lib/djaeger-modem" "$TMP/etc/init.d" "$TMP/etc/config"
get(){ wget -qO "$TMP/$2" --timeout=15 "$BASE/$1" || { echo "Download failed: $1"; exit 1; }; }
get usr/sbin/djaeger-modem usr/sbin/djaeger-modem
get usr/sbin/djaeger-modemd usr/sbin/djaeger-modemd
get usr/lib/djaeger-modem/common.sh usr/lib/djaeger-modem/common.sh
get etc/init.d/djaeger-modem etc/init.d/djaeger-modem
get etc/config/djaeger_modem etc/config/djaeger_modem
for f in "$TMP/usr/sbin/djaeger-modem" "$TMP/usr/sbin/djaeger-modemd" "$TMP/etc/init.d/djaeger-modem"; do sh -n "$f" || { echo "Syntax validation failed: $f"; exit 1; }; done
mkdir -p /root/djaeger-modem "$RB/usr/sbin" "$RB/usr/lib/djaeger-modem" "$RB/etc/init.d" "$RB/etc/config"
for F in usr/sbin/djaeger-modem usr/sbin/djaeger-modemd usr/lib/djaeger-modem/common.sh etc/init.d/djaeger-modem etc/config/djaeger_modem; do [ -f "/$F" ] && cp -f "/$F" "$RB/$F" || true; done
/etc/init.d/djaeger-modem stop >/dev/null 2>&1 || true
# Give procd/old daemon time to exit, then clear only the known singleton lock.
i=0; while [ $i -lt 10 ] && pgrep -f '/usr/sbin/djaeger-modemd' >/dev/null 2>&1; do sleep 1; i=$((i+1)); done
if ! pgrep -f '/usr/sbin/djaeger-modemd' >/dev/null 2>&1; then rm -rf /tmp/djaeger-modem.lock; fi
cp -f "$TMP/usr/sbin/djaeger-modem" /usr/sbin/djaeger-modem; cp -f "$TMP/usr/sbin/djaeger-modemd" /usr/sbin/djaeger-modemd
mkdir -p /usr/lib/djaeger-modem; cp -f "$TMP/usr/lib/djaeger-modem/common.sh" /usr/lib/djaeger-modem/common.sh; cp -f "$TMP/etc/init.d/djaeger-modem" /etc/init.d/djaeger-modem
if [ ! -f /etc/config/djaeger_modem ]; then cp -f "$TMP/etc/config/djaeger_modem" /etc/config/djaeger_modem; else
 uci -q get djaeger_modem.main >/dev/null || uci set djaeger_modem.main=core
 for KV in "enabled=1" "modem_url=http://192.168.8.1" "gateway=192.168.8.1" "interval=15" "confirm_failures=3" "recover_confirmations=2" "recovery_cooldown=300" "max_recoveries_hour=2" "retention_days=14"; do K=${KV%%=*}; V=${KV#*=}; uci -q get "djaeger_modem.main.$K" >/dev/null || uci set "djaeger_modem.main.$K=$V"; done
 # v1.1 migration intentionally enables only safe L1 WAN reconnect. Huawei POST remains locked.
 uci set djaeger_modem.main.self_heal='1'; uci set djaeger_modem.main.allow_wan_reconnect='1'; uci set djaeger_modem.main.allow_modem_post='0'; uci commit djaeger_modem
fi
chmod 755 /usr/sbin/djaeger-modem /usr/sbin/djaeger-modemd /etc/init.d/djaeger-modem; chmod 644 /usr/lib/djaeger-modem/common.sh /etc/config/djaeger_modem
/etc/init.d/djaeger-modem enable >/dev/null 2>&1 || true; /etc/init.d/djaeger-modem start
# Wait up to 12 seconds for procd daemon startup.
i=0; while [ $i -lt 12 ]; do pgrep -f '/usr/sbin/djaeger-modemd' >/dev/null 2>&1 && break; sleep 1; i=$((i+1)); done
if ! pgrep -f '/usr/sbin/djaeger-modemd' >/dev/null 2>&1; then echo 'Health check failed; previous files are preserved in rollback snapshot.'; exit 1; fi
rm -rf "$TMP"
echo 'Installation/update successful.'
echo 'Self-Healing L1: enabled; Huawei POST/reboot: hard-locked.'
sleep 2
djaeger-modem status
