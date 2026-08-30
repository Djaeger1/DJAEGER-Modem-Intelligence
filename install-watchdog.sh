#!/bin/sh
DJAEGER_WATCHDOG_INSTALLER_ID=DJAEGER_FAST_WATCHDOG
set -e
[ "$(id -u)" = 0 ] || exit 1
BASE='https://raw.githubusercontent.com/Djaeger1/DJAEGER-Modem-Intelligence/main'
TMP=/tmp/djaeger-watchdog-install
rm -rf "$TMP"; mkdir -p "$TMP/usr/sbin" "$TMP/etc/init.d"
get(){ wget -qO "$TMP/$1" --timeout=15 "$BASE/$1" || exit 1; [ -s "$TMP/$1" ] || exit 1; }
get usr/sbin/djaeger-watchdog
get etc/init.d/djaeger-watchdog
sh -n "$TMP/usr/sbin/djaeger-watchdog"
sh -n "$TMP/etc/init.d/djaeger-watchdog"
cp -f "$TMP/usr/sbin/djaeger-watchdog" /usr/sbin/djaeger-watchdog
cp -f "$TMP/etc/init.d/djaeger-watchdog" /etc/init.d/djaeger-watchdog
chmod 755 /usr/sbin/djaeger-watchdog /etc/init.d/djaeger-watchdog
/etc/init.d/djaeger-watchdog enable
/etc/init.d/djaeger-watchdog restart >/dev/null 2>&1 || /etc/init.d/djaeger-watchdog start
sleep 3
ps w | grep -q '[d]jaeger-watchdog' || { echo 'WATCHDOG START FAILED'; exit 1; }
echo 'DJAEGER Fast Watchdog: ACTIVE'
cat /tmp/djaeger-watchdog.state 2>/dev/null || true
rm -rf "$TMP"
