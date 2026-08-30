#!/bin/sh
DJAEGER_FAST_WATCHDOG_INSTALLER_ID=DJAEGER_FAST_WATCHDOG_V4_GEMINI_LEARNING
set -e
[ "$(id -u)" = 0 ] || exit 1
B=https://raw.githubusercontent.com/Djaeger1/DJAEGER-Modem-Intelligence/main
get(){ wget -qO "$1" "$B/$2"; [ -s "$1" ]; }
get /tmp/djaeger-fast-watchdog usr/sbin/djaeger-fast-watchdog
get /tmp/djaeger-fast-watchdog.init etc/init.d/djaeger-fast-watchdog
get /tmp/djaeger-local-ai-policy.sh usr/lib/djaeger-modem/local-ai-policy.sh
get /tmp/djaeger-gemini-learning.sh usr/lib/djaeger-modem/gemini-policy-learning.sh
get /tmp/djaeger-gemini-learning.init etc/init.d/djaeger-gemini-learning
for F in /tmp/djaeger-fast-watchdog /tmp/djaeger-fast-watchdog.init /tmp/djaeger-local-ai-policy.sh /tmp/djaeger-gemini-learning.sh /tmp/djaeger-gemini-learning.init; do sh -n "$F"; done
! grep -Eq '(^|[[:space:];])eval([[:space:]]|$)' /tmp/djaeger-fast-watchdog
! grep -Eq '(^|[[:space:];])eval([[:space:]]|$)' /tmp/djaeger-local-ai-policy.sh
for D in common.sh recovery.sh root-broker.sh gemini.sh investigator.sh; do [ -s "/usr/lib/djaeger-modem/$D" ] || { echo "Missing dependency: $D"; exit 1; }; sh -n "/usr/lib/djaeger-modem/$D"; done
mkdir -p /usr/lib/djaeger-modem /root/djaeger-modem
cp -f /tmp/djaeger-fast-watchdog /usr/sbin/djaeger-fast-watchdog
cp -f /tmp/djaeger-fast-watchdog.init /etc/init.d/djaeger-fast-watchdog
cp -f /tmp/djaeger-local-ai-policy.sh /usr/lib/djaeger-modem/local-ai-policy.sh
cp -f /tmp/djaeger-gemini-learning.sh /usr/lib/djaeger-modem/gemini-policy-learning.sh
cp -f /tmp/djaeger-gemini-learning.init /etc/init.d/djaeger-gemini-learning
chmod 755 /usr/sbin/djaeger-fast-watchdog /etc/init.d/djaeger-fast-watchdog /usr/lib/djaeger-modem/local-ai-policy.sh /usr/lib/djaeger-modem/gemini-policy-learning.sh /etc/init.d/djaeger-gemini-learning
/usr/lib/djaeger-modem/local-ai-policy.sh compile
/etc/init.d/djaeger-fast-watchdog restart
/etc/init.d/djaeger-fast-watchdog enable
/etc/init.d/djaeger-gemini-learning enable
/etc/init.d/djaeger-gemini-learning restart
sleep 2
pgrep -f '/usr/sbin/djaeger-fast-watchdog' >/dev/null
[ -s /tmp/djaeger-local-ai.policy ] && [ -s /tmp/djaeger-fast-watchdog.state ]
echo 'DJAEGER FAST WATCHDOG V4 + GEMINI POLICY LEARNING ACTIVE'
cat /tmp/djaeger-fast-watchdog.state
echo '--- LOCAL AI POLICY ---'; cat /tmp/djaeger-local-ai.policy
