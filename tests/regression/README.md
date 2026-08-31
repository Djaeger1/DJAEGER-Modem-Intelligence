# DJAEGER Real Incident Regression Corpus

This directory defines permanent regression cases derived from real DJAEGER-WRT connectivity incidents. These cases are mandatory design constraints for Fast Watchdog, Local AI, Root Broker, Huawei recovery state machine, and post-recovery Gemini policy learning.

## Safety and privacy

Do not commit raw dumps containing IMEI, IMSI, ICCID, serial numbers, MAC addresses, session tokens, API keys, or other credentials. Store only sanitized event/state summaries and synthetic replay fixtures.

## Canonical architecture

Gemini formulates/refines policy while Internet is available -> Local AI validates and stores policy locally -> Fast Watchdog remains ultra-light in healthy standby and provides the fastest outage reflex -> Local AI diagnoses and authorizes typed recovery -> Root Broker executes -> Watchdog returns recovery outcome to Local AI -> after Internet is restored Gemini analyzes the outcome and refines future policy. Gemini is never awaited on the outage critical path.

## Ground-truth family: 2026-08-31 07:10 incident

Observed invariant:

- Internet/upstream failed.
- OpenWrt still had the Huawei local path on eth1.
- Huawei DHCP/gateway path could still provide 192.168.8.100 via 192.168.8.1.
- Repeating WAN reconnect did not reliably restore Internet.
- Huawei reboot cycles enumerate through 12d1:14db -> disconnect -> 12d1:1f01 -> 12d1:14db -> eth1 returns.
- A modem reboot cannot be judged after a fixed ~4 second verification window.
- Recovery can appear as LATE_SUCCESS after the modem has had time to boot, expose API, initialize SIM, discover PLMN, register/attach, establish a data session, and restore Internet.
- User-observed failure episodes can require repeated controlled modem reboots before cellular service returns.

Expected classifier behavior:

- Gateway reachable + OpenWrt DHCP healthy + Internet failed must not automatically be classified as OPENWRT_WAN_FAILURE.
- Distinguish PROVIDER_NOT_VISIBLE, PLMN_VISIBLE_NOT_REGISTERED, REGISTRATION_STUCK, REGISTERED_NO_DATA_SESSION, MODEM_PRESENT_BUT_NO_NETWORK, and upstream/OpenWrt failures using evidence.
- Unknown/zero Huawei radio fields during reboot/API initialization must not automatically be classified as cellular registration failure.

Expected recovery behavior:

1. Fast-confirm Internet loss without disturbing a healthy connection.
2. Capture a minimal pre-recovery black-box snapshot without materially delaying recovery.
3. Local AI determines the failure domain from Huawei + OpenWrt evidence.
4. Use a short L1 WAN recovery only when evidence supports it.
5. If Huawei local path is healthy but Huawei cellular/data state is not, do not loop WAN_RECONNECT.
6. Escalate through typed broker actions.
7. Huawei recovery uses an action-specific state machine: MODEM_REBOOT -> WAIT_BOOT/USB -> WAIT_API -> WAIT_SIM -> WAIT_PLMN -> WAIT_REGISTRATION -> WAIT_DATA_SESSION/WAN_IP -> VERIFY_INTERNET.
8. Allow bounded episode-specific modem retries with complete registration waits and anti-loop protection; do not permanently lock modem recovery after one attempt.
9. Persist the outcome to Local AI.
10. Only after ONLINE, allow Gemini post-analysis/policy refinement.

## Historical regression patterns

The persistent history contained multiple families that future releases must replay:

- CELLULAR_SERVICE_LOST with eventual recovery.
- MODEM_PRESENT_BUT_NO_NETWORK while Huawei local DHCP/gateway remains reachable.
- UPSTREAM_OR_DATA_SESSION ambiguity that requires evidence rather than blind WAN reconnect.
- Long RECOVERING state that must not be interpreted as a literal continuous outage without corroboration.
- Repeated WAN_RECONNECT decisions despite cellular/modem evidence.
- WAN_RECONNECT -> NETIFD_RESTART -> MODEM_REBOOT followed by delayed/late success.

## Mandatory release gates

A candidate must fail release if it:

- waits for Gemini while Internet is down;
- directly executes arbitrary Gemini/cloud shell text;
- loops WAN reconnect when Huawei local networking is healthy and cellular/data state is the failing domain;
- treats MODEM_REBOOT as failed before the Huawei registration state machine completes or times out;
- restarts LAN unnecessarily for a modem/cellular failure;
- contaminates healthy-state learning with outage/recovery samples;
- loses the ability to restore/verify normal network state;
- permits unbounded reboot/recovery loops.

Every future release should be checked with static audit, deterministic state-machine simulation, sanitized historical/synthetic telemetry replay, failure tests, and safety regression before hardware validation.
