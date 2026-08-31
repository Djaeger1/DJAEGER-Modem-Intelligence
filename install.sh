#!/bin/sh
# DJAEGER Cellular Autonomous Control Plane - transactional production installer
set -eu
[ "$(id -u)" = 0 ]||{ echo 'ERROR: run as root';exit 1; }
BASE='https://raw.githubusercontent.com/Djaeger1/DJAEGER-Modem-Intelligence/main';TMP="/tmp/djaeger-release.$$";TS="$(date +%s)";RB="/root/djaeger-modem/rollback/release-$TS";STAGE=INIT;mkdir -p "$TMP" "$RB"
FILES='usr/sbin/djaeger-modem usr/sbin/djaeger-modemd usr/sbin/djaeger-fast-watchdog usr/lib/djaeger-modem/common.sh usr/lib/djaeger-modem/adaptive.sh usr/lib/djaeger-modem/gemini.sh usr/lib/djaeger-modem/recovery.sh usr/lib/djaeger-modem/system-intelligence.sh usr/lib/djaeger-modem/rootcause.sh usr/lib/djaeger-modem/investigator.sh usr/lib/djaeger-modem/root-broker.sh usr/lib/djaeger-modem/decision-engine.sh usr/lib/djaeger-modem/local-ai-policy.sh usr/lib/djaeger-modem/cellular-state-engine.sh usr/lib/djaeger-modem/connection-governor.sh etc/init.d/djaeger-modem etc/config/djaeger_modem policy/providers/xl.policy tests/regression/replay-v1.sh'
get(){ mkdir -p "$TMP/$(dirname "$1")";wget -qO "$TMP/$1" --timeout=15 "$BASE/$1"||{ command -v curl >/dev/null&&curl -fsSL --max-time 30 -o "$TMP/$1" "$BASE/$1"; };[ -s "$TMP/$1" ]; }
for F in $FILES;do get "$F"||{ echo "DOWNLOAD_FAIL $F";rm -rf "$TMP";exit 1; };done
STAGE=STATIC_AUDIT
for F in $FILES;do case "$F" in *.sh|usr/sbin/*|etc/init.d/*) sh -n "$TMP/$F"||{ echo "SYNTAX_FAIL $F";rm -rf "$TMP";exit 1; };;esac;done
chmod +x "$TMP/tests/regression/replay-v1.sh";"$TMP/tests/regression/replay-v1.sh"||{ echo 'REGRESSION_FAIL';rm -rf "$TMP";exit 1; }
STAGE=BACKUP
for P in /usr/sbin/djaeger-modem /usr/sbin/djaeger-modemd /usr/sbin/djaeger-fast-watchdog /usr/lib/djaeger-modem /etc/init.d/djaeger-modem /etc/config/djaeger_modem /usr/share/djaeger-modem;do [ -e "$P" ]&&{ mkdir -p "$RB$(dirname "$P")";cp -a "$P" "$RB$P"; }||true;done
rollback(){ echo "INSTALL_FAIL stage=$STAGE: rolling back";/etc/init.d/djaeger-modem stop >/dev/null 2>&1||true;for P in /usr/sbin/djaeger-modem /usr/sbin/djaeger-modemd /usr/sbin/djaeger-fast-watchdog /usr/lib/djaeger-modem /etc/init.d/djaeger-modem /etc/config/djaeger_modem /usr/share/djaeger-modem;do rm -rf "$P";[ -e "$RB$P" ]&&{ mkdir -p "$(dirname "$P")";cp -a "$RB$P" "$P"; }||true;done;[ -x /etc/init.d/djaeger-modem ]&&/etc/init.d/djaeger-modem start >/dev/null 2>&1||true;rm -rf "$TMP";exit 1;};trap rollback INT TERM HUP
STAGE=INSTALL;/etc/init.d/djaeger-modem stop >/dev/null 2>&1||true;mkdir -p /usr/lib/djaeger-modem /usr/share/djaeger-modem/providers
cp -f "$TMP/usr/sbin/djaeger-modem" "$TMP/usr/sbin/djaeger-modemd" "$TMP/usr/sbin/djaeger-fast-watchdog" /usr/sbin/;cp -f "$TMP/usr/lib/djaeger-modem/"*.sh /usr/lib/djaeger-modem/;cp -f "$TMP/etc/init.d/djaeger-modem" /etc/init.d/djaeger-modem;[ -f /etc/config/djaeger_modem ]||cp -f "$TMP/etc/config/djaeger_modem" /etc/config/djaeger_modem;cp -f "$TMP/policy/providers/xl.policy" /usr/share/djaeger-modem/providers/xl.policy
# Library modules are also standalone typed tools (cellular engine/governor/local AI); keep them executable.
chmod 755 /usr/sbin/djaeger-* /etc/init.d/djaeger-modem /usr/lib/djaeger-modem/*.sh;chmod 644 /usr/share/djaeger-modem/providers/xl.policy
for KV in self_heal=1 allow_wan_reconnect=1 allow_service_recovery=1 allow_dnsmasq_restart=1 allow_netifd_restart=1 allow_modem_post=1 allow_modem_reboot=1 autonomous_root_recovery=1 traffic_governor=0 broker_wan_cooldown=30 broker_wan_max_hour=6 broker_dns_cooldown=120 broker_dns_max_hour=3 broker_netifd_cooldown=120 broker_netifd_max_hour=3 modem_reboot_cooldown=120 max_modem_reboots_hour=3;do K=${KV%%=*};V=${KV#*=};uci set "djaeger_modem.main.$K=$V";done;uci commit djaeger_modem
STAGE=SERVICE_START;/etc/init.d/djaeger-modem enable >/dev/null 2>&1||true;/etc/init.d/djaeger-modem start||rollback;sleep 5
ps w|grep -q '[d]jaeger-modemd'||rollback
STAGE=CELLULAR_SMOKE_TEST
/usr/lib/djaeger-modem/cellular-state-engine.sh >/dev/null 2>&1||rollback
[ -s /tmp/djaeger-modem/cellular-state ]||rollback
STAGE=COMPLETE;rm -rf "$TMP";trap - INT TERM HUP
echo 'DJAEGER RELEASE GATE: PASS';echo "Rollback snapshot: $RB";echo 'Adaptive Connection Governor: OFF (safe default)'
