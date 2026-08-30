#!/bin/sh
DJAEGER_FAST_WATCHDOG_INSTALLER_ID=DJAEGER_FAST_WATCHDOG
set -e
[ "$(id -u)" = 0 ] || exit 1
B=https://raw.githubusercontent.com/Djaeger1/DJAEGER-Modem-Intelligence/main
wget -qO /tmp/djaeger-fast-watchdog "$B/usr/sbin/djaeger-fast-watchdog"
wget -qO /tmp/djaeger-fast-watchdog.init "$B/etc/init.d/djaeger-fast-watchdog"
sh -n /tmp/djaeger-fast-watchdog; sh -n /tmp/djaeger-fast-watchdog.init
cp -f /tmp/djaeger-fast-watchdog /usr/sbin/djaeger-fast-watchdog
cp -f /tmp/djaeger-fast-watchdog.init /etc/init.d/djaeger-fast-watchdog
chmod 755 /usr/sbin/djaeger-fast-watchdog /etc/init.d/djaeger-fast-watchdog
/etc/init.d/djaeger-fast-watchdog stop >/dev/null 2>&1 || true
/etc/init.d/djaeger-fast-watchdog enable
/etc/init.d/djaeger-fast-watchdog start
sleep 2
pgrep -f '/usr/sbin/djaeger-fast-watchdog' >/dev/null
[ -f /tmp/djaeger-fast-watchdog.state ]
echo 'DJAEGER FAST WATCHDOG ACTIVE'
cat /tmp/djaeger-fast-watchdog.state
