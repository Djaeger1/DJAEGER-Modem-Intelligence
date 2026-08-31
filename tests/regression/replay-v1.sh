#!/bin/sh
# DJAEGER deterministic regression replay v3 - mirrors runtime state/escalation invariants.
set -u
PASS=0;FAIL=0;ok(){ PASS=$((PASS+1));printf 'PASS  %s\n' "$1";};bad(){ FAIL=$((FAIL+1));printf 'FAIL  %s\n' "$1";}
classify(){ internet="$1";gateway="$2";dhcp="$3";api="$4";sim="$5";plmn="$6";attached="$7";service="$8";modem_ip="$9";age="${10}";phase="${11}";[ "$phase" = READY ]||{ echo MODEM_TRANSITION;return;};[ "$internet" = 0 ]||{ echo HEALTHY;return;};[ "$gateway" = 1 ]&&[ "$dhcp" = 1 ]||{ echo OPENWRT_WAN_OR_MODEM_PATH;return;};[ "$api" = 1 ]||{ echo MODEM_API_UNAVAILABLE;return;};[ "$sim" = 1 ]||{ echo SIM_OR_SERVICE_FAILURE;return;};[ "$plmn" = 1 ]||{ echo RADIO_OR_PROVIDER_UNAVAILABLE;return;};if [ "$attached" = 0 ];then [ "$age" -ge 20 ]&&echo REGISTRATION_STUCK||echo PLMN_VISIBLE_NOT_REGISTERED;return;fi;[ "$service" = 1 ]||{ echo MODEM_PROVIDER;return;};[ "$modem_ip" = 1 ]||{ echo REGISTERED_NO_DATA_SESSION;return;};echo DATA_SESSION_STALLED; }
expect(){ name="$1";want="$2";shift 2;got="$(classify "$@")";[ "$got" = "$want" ]&&ok "$name => $got"||bad "$name => $got expected=$want"; }
expect healthy HEALTHY 1 1 1 1 1 1 1 1 1 0 READY
expect incident_0710_initial PLMN_VISIBLE_NOT_REGISTERED 0 1 1 1 1 1 0 0 0 3 READY
expect incident_0710_sustained REGISTRATION_STUCK 0 1 1 1 1 1 0 0 0 25 READY
expect registered_no_pdp REGISTERED_NO_DATA_SESSION 0 1 1 1 1 1 1 1 0 0 READY
expect data_session_stalled DATA_SESSION_STALLED 0 1 1 1 1 1 1 1 1 0 READY
expect huawei_boot MODEM_TRANSITION 0 0 0 0 0 0 0 0 0 0 WAIT_BOOT
expect modem_api_unavailable MODEM_API_UNAVAILABLE 0 1 1 0 0 0 0 0 0 0 READY
expect provider_not_visible RADIO_OR_PROVIDER_UNAVAILABLE 0 1 1 1 1 0 0 0 0 0 READY
plan(){ case "$1" in PLMN_VISIBLE_NOT_REGISTERED|REGISTRATION_STUCK|RADIO_OR_PROVIDER_UNAVAILABLE|MODEM_API_UNAVAILABLE|SIM_OR_SERVICE_FAILURE|MODEM_PROVIDER)echo MODEM_REBOOT,MODEM_REBOOT,NETIFD_RESTART;;REGISTERED_NO_DATA_SESSION|DATA_SESSION_STALLED)echo WAN_RECONNECT,MODEM_REBOOT,MODEM_REBOOT;;OPENWRT_WAN_OR_MODEM_PATH)echo WAN_RECONNECT,NETIFD_RESTART,MODEM_REBOOT;;HEALTHY)echo NONE,NONE,NONE;;*)echo WAN_RECONNECT,NETIFD_RESTART,MODEM_REBOOT;;esac; }
[ "$(plan REGISTRATION_STUCK)" = MODEM_REBOOT,MODEM_REBOOT,NETIFD_RESTART ]&&ok '0710 sustained failure bypasses WAN reconnect'||bad '0710 policy'
# Episode-memory simulation: repeated entries in policy do not repeat a failed action.
next(){ P="$1";F="$2";OLDIFS="$IFS";IFS=,;set -- $P;IFS="$OLDIFS";for A in "$@";do [ "$A" = NONE ]&&continue;case ",$F," in *,$A,*)continue;;esac;echo "$A";return;done;echo NONE; }
P="$(plan REGISTERED_NO_DATA_SESSION)";A="$(next "$P" '')";[ "$A" = WAN_RECONNECT ]&&ok 'data session first L1 WAN reconnect'||bad 'first escalation';A="$(next "$P" WAN_RECONNECT)";[ "$A" = MODEM_REBOOT ]&&ok 'failed WAN escalates to modem'||bad 'WAN repeated';A="$(next "$P" WAN_RECONNECT,MODEM_REBOOT)";[ "$A" = NONE ]&&ok 'failed modem is not repeated blindly'||bad 'modem repeated'
[ "$(plan HEALTHY)" = NONE,NONE,NONE ]&&ok 'healthy untouched'||bad 'healthy invariant'
phases='WAIT_BOOT WAIT_API WAIT_SIM WAIT_PLMN WAIT_REGISTRATION WAIT_DATA_SESSION VERIFY_INTERNET';n=0;for p in $phases;do n=$((n+1));done;[ "$n" -eq 7 ]&&ok 'seven phase recovery'||bad 'phase count'
printf '\nRESULT pass=%s fail=%s\n' "$PASS" "$FAIL";[ "$FAIL" -eq 0 ]
