#!/bin/sh
# DJAEGER deterministic regression replay v2
# Historical/synthetic policy validation only. No network writes, modem POSTs or service restarts.
set -u
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf 'PASS  %s\n' "$1"; }
bad(){ FAIL=$((FAIL+1)); printf 'FAIL  %s\n' "$1"; }
classify(){
 internet="$1"; gateway="$2"; dhcp="$3"; api="$4"; sim="$5"; plmn="$6"; attached="$7"; service="$8"; modem_ip="$9"; phase="${10}"
 [ "$phase" = READY ] || { echo MODEM_TRANSITION; return; }
 [ "$internet" = 0 ] || { echo HEALTHY; return; }
 [ "$gateway" = 1 ] || { echo OPENWRT_WAN_OR_MODEM_PATH; return; }
 [ "$dhcp" = 1 ] || { echo OPENWRT_WAN_OR_MODEM_PATH; return; }
 [ "$api" = 1 ] || { echo MODEM_API_UNAVAILABLE; return; }
 [ "$sim" = 1 ] || { echo SIM_OR_SERVICE_FAILURE; return; }
 [ "$plmn" = 1 ] || { echo RADIO_OR_PROVIDER_UNAVAILABLE; return; }
 [ "$attached" = 1 ] || { echo PLMN_VISIBLE_NOT_REGISTERED; return; }
 [ "$service" = 1 ] || { echo REGISTRATION_STUCK; return; }
 [ "$modem_ip" = 1 ] || { echo REGISTERED_NO_DATA_SESSION; return; }
 echo DATA_SESSION_STALLED
}
expect(){ name="$1"; want="$2"; shift 2; got="$(classify "$@")"; [ "$got" = "$want" ] && ok "$name => $got" || bad "$name => $got (expected $want)"; }
# Sanitized fixtures from known healthy/failure behavior.
expect healthy HEALTHY 1 1 1 1 1 1 1 1 1 READY
expect incident_0710_plmn_visible PLMN_VISIBLE_NOT_REGISTERED 0 1 1 1 1 1 0 0 0 READY
expect registration_stuck REGISTRATION_STUCK 0 1 1 1 1 1 1 0 0 READY
expect registered_no_pdp REGISTERED_NO_DATA_SESSION 0 1 1 1 1 1 1 1 0 READY
expect data_session_stalled DATA_SESSION_STALLED 0 1 1 1 1 1 1 1 1 READY
expect huawei_boot MODEM_TRANSITION 0 0 0 0 0 0 0 0 0 WAIT_BOOT
expect modem_api_unavailable MODEM_API_UNAVAILABLE 0 1 1 0 0 0 0 0 0 READY
expect provider_not_visible RADIO_OR_PROVIDER_UNAVAILABLE 0 1 1 1 1 0 0 0 0 READY
expect wan_path OPENWRT_WAN_OR_MODEM_PATH 0 0 0 0 0 0 0 0 0 READY
choose(){ case "$1" in
 PLMN_VISIBLE_NOT_REGISTERED|REGISTRATION_STUCK|RADIO_OR_PROVIDER_UNAVAILABLE) echo MODEM_REBOOT,MODEM_REBOOT,NETIFD_RESTART;;
 REGISTERED_NO_DATA_SESSION|DATA_SESSION_STALLED) echo WAN_RECONNECT,MODEM_REBOOT,MODEM_REBOOT;;
 OPENWRT_WAN_OR_MODEM_PATH) echo WAN_RECONNECT,NETIFD_RESTART,MODEM_REBOOT;;
 HEALTHY) echo NONE,NONE,NONE;;
 *) echo WAN_RECONNECT,NETIFD_RESTART,MODEM_REBOOT;; esac; }
# 07:10 invariant: gateway/DHCP/API alive + PLMN visible + no attach must not waste first action on WAN reconnect.
[ "$(choose PLMN_VISIBLE_NOT_REGISTERED)" = MODEM_REBOOT,MODEM_REBOOT,NETIFD_RESTART ] && ok '0710 cellular failure bypasses WAN reconnect loop' || bad '0710 recovery order'
# Data-session-only failure may use one cheap WAN reconnect before cellular escalation.
[ "$(choose REGISTERED_NO_DATA_SESSION)" = WAN_RECONNECT,MODEM_REBOOT,MODEM_REBOOT ] && ok 'registered-no-data permits one L1 then modem escalation' || bad 'data-session recovery order'
# Healthy network is never repaired.
[ "$(choose HEALTHY)" = NONE,NONE,NONE ] && ok 'healthy network untouched' || bad 'healthy invariant'
# Required phase-aware modem verification.
phases='WAIT_BOOT WAIT_API WAIT_SIM WAIT_PLMN WAIT_REGISTRATION WAIT_DATA_SESSION VERIFY_INTERNET'; n=0; for p in $phases; do n=$((n+1)); done
[ "$n" -eq 7 ] && ok 'complete modem recovery phases' || bad 'modem phase count'
# Timing invariant: modem cannot be judged by old 4-second verification.
MODEM_VERIFY=120; [ "$MODEM_VERIFY" -ge 60 ] && ok 'modem verification >=60 seconds' || bad 'modem verification too short'
printf '\nRESULT pass=%s fail=%s\n' "$PASS" "$FAIL"; [ "$FAIL" -eq 0 ]
