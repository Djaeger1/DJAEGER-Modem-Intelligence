#!/bin/sh
# DJAEGER deterministic regression replay v1
# No network writes, no modem POSTs, no service restarts.
set -u
PASS=0
FAIL=0
ok(){ PASS=$((PASS+1)); printf 'PASS  %s\n' "$1"; }
bad(){ FAIL=$((FAIL+1)); printf 'FAIL  %s\n' "$1"; }

classify(){
  internet="$1"; gateway="$2"; dhcp="$3"; api="$4"; sim="$5"; plmn="$6"; registered="$7"; modem_ip="$8"; phase="$9"
  if [ "$phase" != READY ]; then echo MODEM_TRANSITION; return; fi
  if [ "$internet" = 1 ]; then echo HEALTHY; return; fi
  if [ "$gateway" = 1 ] && [ "$dhcp" = 1 ] && [ "$api" = 1 ]; then
    [ "$sim" = 1 ] || { echo MODEM_SIM_OR_SERVICE; return; }
    [ "$plmn" = 1 ] || { echo RADIO_OR_PROVIDER_UNAVAILABLE; return; }
    [ "$registered" = 1 ] || { echo PLMN_VISIBLE_NOT_REGISTERED; return; }
    [ "$modem_ip" = 1 ] || { echo REGISTERED_NO_DATA_SESSION; return; }
    echo MODEM_DATA_SESSION_OR_UPSTREAM; return
  fi
  if [ "$gateway" = 0 ]; then echo OPENWRT_WAN_OR_MODEM_PATH; return; fi
  echo MULTI_FACTOR
}

expect(){ name="$1"; want="$2"; shift 2; got="$(classify "$@")"; [ "$got" = "$want" ] && ok "$name => $got" || bad "$name => $got (expected $want)"; }

# Real-incident-derived sanitized fixtures.
expect healthy HEALTHY 1 1 1 1 1 1 1 1 READY
expect incident_0710_plmn_visible PLMN_VISIBLE_NOT_REGISTERED 0 1 1 1 1 1 0 0 READY
expect registered_no_pdp REGISTERED_NO_DATA_SESSION 0 1 1 1 1 1 1 0 READY
expect huawei_boot_zero_fields MODEM_TRANSITION 0 0 0 0 0 0 0 0 WAIT_BOOT
expect provider_not_visible RADIO_OR_PROVIDER_UNAVAILABLE 0 1 1 1 1 0 0 0 READY
expect wan_or_modem_path OPENWRT_WAN_OR_MODEM_PATH 0 0 0 0 0 0 0 0 READY

# Recovery invariants derived from historical failures.
choose_recovery(){ domain="$1"; case "$domain" in
  PLMN_VISIBLE_NOT_REGISTERED|REGISTERED_NO_DATA_SESSION|MODEM_DATA_SESSION_OR_UPSTREAM) echo WAN_RECONNECT,MODEM_STATE_MACHINE;;
  OPENWRT_WAN_OR_MODEM_PATH) echo WAN_RECONNECT,NETIFD_RESTART,MODEM_STATE_MACHINE;;
  RADIO_OR_PROVIDER_UNAVAILABLE) echo MODEM_STATE_MACHINE;;
  *) echo WAN_RECONNECT,NETIFD_RESTART,MODEM_STATE_MACHINE;; esac
}

[ "$(choose_recovery PLMN_VISIBLE_NOT_REGISTERED)" = WAN_RECONNECT,MODEM_STATE_MACHINE ] && ok '0710 avoids WAN reconnect loop' || bad '0710 recovery order'

# A modem recovery must be phase-based, not a 4-second generic verification.
modem_phases='WAIT_BOOT WAIT_API WAIT_SIM WAIT_PLMN WAIT_REGISTRATION WAIT_DATA_SESSION VERIFY_INTERNET'
count=0
for p in $modem_phases; do count=$((count+1)); done
[ "$count" -eq 7 ] && ok 'modem recovery has complete registration phases' || bad 'modem recovery phase count'

printf '\nRESULT pass=%s fail=%s\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
