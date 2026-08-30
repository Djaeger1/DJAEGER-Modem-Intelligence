#!/bin/sh
DJAEGER_MONITOR_BRIDGE_INSTALLER_ID=DJAEGER_MODEM_MONITOR_BRIDGE
set -eu
[ "$(id -u)" = 0 ] || { echo 'Run as root'; exit 1; }
BASE='https://raw.githubusercontent.com/Djaeger1/DJAEGER-Modem-Intelligence/main'
TMP=/tmp/djaeger-monitor-bridge-install
rm -rf "$TMP"; mkdir -p "$TMP"
get(){
  src="$1"; dst="$2"; i=0
  while [ "$i" -lt 3 ]; do
    if wget -qO "$dst" --timeout=15 "$BASE/$src" && [ -s "$dst" ]; then return 0; fi
    i=$((i+1)); sleep "$i"
  done
  if command -v curl >/dev/null 2>&1 && curl -fsSL --connect-timeout 10 --max-time 30 --retry 2 -o "$dst" "$BASE/$src" && [ -s "$dst" ]; then return 0; fi
  echo "Download failed: $src"; exit 1
}
get usr/lib/djaeger-modem/monitor-bridge.sh "$TMP/monitor-bridge.sh"
get etc/init.d/djaeger-monitor-bridge "$TMP/djaeger-monitor-bridge"
sh -n "$TMP/monitor-bridge.sh"; sh -n "$TMP/djaeger-monitor-bridge"
grep -q '^STATE=/tmp/djaeger-modem/state$' "$TMP/monitor-bridge.sh"
! grep -Eq 'IMEI|IMSI|ICCID|serial|mac=' "$TMP/monitor-bridge.sh" || { echo 'Privacy audit failed'; exit 1; }
# BusyBox/OpenWrt images may not provide GNU/coreutils install(1).
mkdir -p /usr/lib/djaeger-modem /etc/init.d /www/djaeger-modem
cp -f "$TMP/monitor-bridge.sh" /usr/lib/djaeger-modem/monitor-bridge.sh
cp -f "$TMP/djaeger-monitor-bridge" /etc/init.d/djaeger-monitor-bridge
chmod 755 /usr/lib/djaeger-modem/monitor-bridge.sh /etc/init.d/djaeger-monitor-bridge
/etc/init.d/djaeger-monitor-bridge enable
/etc/init.d/djaeger-monitor-bridge restart
sleep 2
[ -s /www/djaeger-modem/status ] || { echo 'Bridge runtime verification failed'; exit 1; }
grep -q '^version=1$' /www/djaeger-modem/status
grep -q '^state=' /www/djaeger-modem/status
grep -q '^root_domain=' /www/djaeger-modem/status
echo 'DJAEGER Monitor Bridge installed and verified.'
echo 'Endpoint: http://192.168.1.1/djaeger-modem/status'
rm -rf "$TMP"
