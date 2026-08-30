#!/bin/sh
DJAEGER_INSTALLER_ID=DJAEGER_MODEM_INTELLIGENCE
set -e
[ "$(id -u)" = 0 ] || { echo 'Run as root'; exit 1; }
BASE='https://raw.githubusercontent.com/Djaeger1/DJAEGER-Modem-Intelligence/main'; TMP='/tmp/djaeger-recovery'; TS="$(date +%s)"; RB="/root/djaeger-modem/rollback/pre-recovery-$TS"
echo 'DJAEGER Modem Intelligence - Autonomous Recovery'
rm -rf "$TMP"; mkdir -p "$TMP/usr/sbin" "$TMP/usr/lib/djaeger-modem" "$TMP/etc/init.d" "$TMP/etc/config"
get(){ D="$TMP/$2"; wget -qO "$D" --timeout=15 "$BASE/$1" || { command -v curl >/dev/null && curl -fsSL --max-time 30 -o "$D" "$BASE/$1"; }; [ -s "$D" ]; }
FILES='usr/sbin/djaeger-modem usr/sbin/djaeger-modemd usr/lib/djaeger-modem/common.sh usr/lib/djaeger-modem/adaptive.sh usr/lib/djaeger-modem/gemini.sh usr/lib/djaeger-modem/recovery.sh usr/lib/djaeger-modem/system-intelligence.sh usr/lib/djaeger-modem/rootcause.sh usr/lib/djaeger-modem/investigator.sh usr/lib/djaeger-modem/root-broker.sh usr/lib/djaeger-modem/decision-engine.sh etc/init.d/djaeger-modem etc/config/djaeger_modem'
for F in $FILES; do get "$F" "$F" || { echo "Download failed: $F"; exit 1; }; done
for F in usr/sbin/djaeger-modem usr/sbin/djaeger-modemd usr/lib/djaeger-modem/*.sh etc/init.d/djaeger-modem; do sh -n "$TMP/$F" || exit 1; done
mkdir -p "$RB"; cp -a /etc/config/djaeger_modem "$RB/config" 2>/dev/null || true; cp -a /usr/sbin/djaeger-modemd "$RB/daemon" 2>/dev/null || true; cp -a /usr/lib/djaeger-modem/root-broker.sh "$RB/root-broker.sh" 2>/dev/null || true
/etc/init.d/djaeger-modem stop >/dev/null 2>&1 || true; sleep 2; rm -rf /tmp/djaeger-modem.lock
cp -f "$TMP/usr/sbin/djaeger-modem" "$TMP/usr/sbin/djaeger-modemd" /usr/sbin/; mkdir -p /usr/lib/djaeger-modem; cp -f "$TMP/usr/lib/djaeger-modem/"*.sh /usr/lib/djaeger-modem/; cp -f "$TMP/etc/init.d/djaeger-modem" /etc/init.d/djaeger-modem
[ -f /etc/config/djaeger_modem ] || cp -f "$TMP/etc/config/djaeger_modem" /etc/config/djaeger_modem
for KV in self_heal=1 allow_wan_reconnect=1 allow_service_recovery=1 allow_dnsmasq_restart=1 allow_netifd_restart=1 allow_modem_post=1 allow_modem_reboot=1 autonomous_root_recovery=1 interval=10 confirm_failures=2 recover_confirmations=2 recovery_verify_wait=20 recovery_cooldown=120 max_recoveries_hour=3 broker_wan_cooldown=120 broker_wan_max_hour=3 broker_dns_cooldown=300 broker_dns_max_hour=2 broker_netifd_cooldown=600 broker_netifd_max_hour=1 modem_reboot_cooldown=900 max_modem_reboots_hour=1; do K=${KV%%=*}; V=${KV#*=}; uci set "djaeger_modem.main.$K=$V"; done
uci commit djaeger_modem
chmod 755 /usr/sbin/djaeger-modem /usr/sbin/djaeger-modemd /etc/init.d/djaeger-modem; chmod 644 /usr/lib/djaeger-modem/*.sh
/etc/init.d/djaeger-modem enable >/dev/null 2>&1 || true; rm -f /tmp/djaeger-modem/state; /etc/init.d/djaeger-modem start
sleep 12
ps w | grep -q '[d]jaeger-modemd' || { echo 'Daemon failed'; exit 1; }
[ -f /tmp/djaeger-modem/state ] || { echo 'State failed'; exit 1; }
for K in allow_service_recovery allow_dnsmasq_restart allow_netifd_restart allow_modem_post allow_modem_reboot autonomous_root_recovery; do [ "$(uci -q get djaeger_modem.main.$K)" = 1 ] || { echo "Authority failed: $K"; exit 1; }; done
echo 'AUTONOMOUS RECOVERY ACTIVE'
djaeger-modem status
