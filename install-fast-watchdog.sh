#!/bin/sh
DJAEGER_FAST_WATCHDOG_INSTALLER_ID=DJAEGER_FAST_WATCHDOG_V3_AUDITED
set -e
[ "$(id -u)" = 0 ] || exit 1
B=https://raw.githubusercontent.com/Djaeger1/DJAEGER-Modem-Intelligence/main
get(){ wget -qO "$1" "$B/$2"; [ -s "$1" ]; }
get /tmp/djaeger-fast-watchdog usr/sbin/djaeger-fast-watchdog
get /tmp/djaeger-fast-watchdog.init etc/init.d/djaeger-fast-watchdog
get /tmp/djaeger-local-ai-policy.sh usr/lib/djaeger-modem/local-ai-policy.sh
for F in /tmp/djaeger-fast-watchdog /tmp/djaeger-fast-watchdog.init /tmp/djaeger-local-ai-policy.sh; do sh -n "$F"; done
# hard safety regression gates
! grep -Eq '(^|[[:space:];])eval([[:space:]]|$)|sh[[:space:]]+-c' /tmp/djaeger-fast-watchdog
for D in common.sh recovery.sh root-broker.sh; do [ -s "/usr/lib/djaeger-modem/$D" ] || { echo "Missing dependency: $D"; exit 1; }; sh -n "/usr/lib/djaeger-modem/$D"; done
mkdir -p /usr/lib/djaeger-modem /root/djaeger-modem
cp -f /usr/sbin/djaeger-fast-watchdog /root/djaeger-modem/djaeger-fast-watchdog.pre-v3 2>/dev/null || true
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
[ -s /tmp/djaeger-local-ai.policy ] && [ -s /tmp/djaeger-fast-watchdog.state ]
echo 'DJAEGER FAST WATCHDOG V3 AUDITED ACTIVE'
cat /tmp/djaeger-fast-watchdog.state
echo '--- LOCAL AI POLICY ---'; cat /tmp/djaeger-local-ai.policy
