#!/bin/sh
# DJAEGER OpenWrt recovery authority regression v4
set -u
ROOT="${1:-.}"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); echo "PASS  $1"; }
bad(){ FAIL=$((FAIL+1)); echo "FAIL  $1"; }
has(){ grep -q "$2" "$ROOT/$1" 2>/dev/null; }
not_has(){ ! grep -q "$2" "$ROOT/$1" 2>/dev/null; }

# Runtime contract errors observed on 2026-09-01 must never return.
not_has usr/sbin/djaeger-modemd 'broker_verify;' && ok 'no undefined broker_verify call' || bad 'undefined broker_verify call'
has usr/sbin/djaeger-modemd 'broker_verify_result LOCAL' && ok 'implemented broker verifier used' || bad 'broker verifier contract'
has usr/lib/djaeger-modem/recovery.sh 'recovery_learn()' && ok 'recovery_learn defined' || bad 'recovery_learn missing'

# Single-writer recovery invariant.
not_has usr/sbin/djaeger-watchdog 'ifup wan' && ok 'legacy watchdog observer-only' || bad 'legacy watchdog still executes WAN recovery'
not_has usr/sbin/djaeger-fast-watchdog 'broker_execute' && ok 'fast watchdog observer-only' || bad 'fast watchdog still executes broker recovery'
has usr/sbin/djaeger-modemd 'broker_execute LOCAL' && ok 'modemd is recovery requester' || bad 'modemd recovery authority missing'

# Cellular semantics from real outage: service lost/registration stuck must not waste first action on WAN reconnect.
has usr/sbin/djaeger-modemd 'REGISTRATION_STUCK' && ok 'registration-stuck domain handled' || bad 'registration-stuck missing'
has usr/sbin/djaeger-modemd 'MODEM_REBOOT; return;' && ok 'cellular hard-failure can reboot modem' || bad 'cellular modem escalation missing'

# Root broker still owns safety policy/budget.
has usr/lib/djaeger-modem/root-broker.sh 'broker_budget' && ok 'broker budget retained' || bad 'broker budget missing'
has usr/lib/djaeger-modem/root-broker.sh 'allow_modem_reboot' && ok 'modem reboot policy lock retained' || bad 'modem reboot lock missing'

printf '\nRESULT pass=%s fail=%s\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
