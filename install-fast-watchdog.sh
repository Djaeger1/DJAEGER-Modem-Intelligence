#!/bin/sh
DJAEGER_FAST_WATCHDOG_INSTALLER_ID=DJAEGER_FAST_WATCHDOG_V2_LOCAL_AI
set -e
[ "$(id -u)" = 0 ] || exit 1
B=https://raw.githubusercontent.com/Djaeger1/DJAEGER-Modem-Intelligence/main
wget -qO /tmp/djaeger-fast-watchdog "$B/usr/sbin/djaeger-fast-watchdog"
wget -qO /tmp/djaeger-fast-watchdog.init "$B/etc/init.d/djaeger-fast-watchdog"
wget -qO /tmp/djaeger-local-ai-policy.sh "$B/usr/lib/djaeger-modem/local-ai-policy.sh"
sh -n /tmp/djaeger-fast-watchdog
sh -n /tmp/djaeger-fast-watchdog.init
sh -n /tmp/djaeger-local-ai-policy.sh
mkdir -p /usr/lib/djaeger-modem
cp -f /tmp/djaeger-fast-watchdog /usr/sbin/djaeger-fast-watchdog
cp -f /tmp/djaeger-fast-watchdog.init /etc/init.d/djaeger-fast-watchdog
cp -f /tmp/djaeger-local-ai-policy.sh /usr/lib/djaeger-modem/local-ai-policy.sh
chmod 755 /usr/sbin/djaeger-fast-watchdog /etc/init.d/djaeger-fast-watchdog /usr/lib/djaeger-modem/local-ai-policy.sh
/usr/lib/djaeger-modem/local-ai-policy.sh compile
/etc/init.d/djaeger-fast-watchdog stop >/dev/null 2>&1 || true
/etc/init.d/djaeger-fast-watchdog enable
/etc/init.d/djaeger-fast-watchdog start
sleep 2
pgrep -f '/usr/sbin/djaeger-fast-watchdog' >/dev/null
[ -s /tmp/djaeger-local-ai.policy ]
[ -s /tmp/djaeger-fast-watchdog.state ]
echo 'DJAEGER FAST WATCHDOG V2 + LOCAL AI POLICY ACTIVE'
cat /tmp/djaeger-fast-watchdog.state
echo '--- LOCAL AI POLICY ---'
cat /tmp/djaeger-local-ai.policy
