# DJAEGER Cellular Intelligence

DJAEGER is an autonomous Internet-availability controller specialized in the cellular path between modem, mobile provider, and Internet.

Primary mission: Maximum Internet Availability with Minimum Unnecessary Intervention.

DJAEGER is not a generic OpenWrt optimizer. OpenWrt is the observation and controlled-execution platform. Intelligence centers on:

OpenWrt -> Modem -> SIM -> PLMN/Provider -> Registration -> Packet Attach -> Data Session -> Provider IP -> Internet

Core architecture:

- Fast Watchdog: ultra-light outage reflex.
- Local AI: offline-capable real-time cellular authority.
- Cellular State Engine: modem boot, API, SIM, PLMN, registration, attach and data-session diagnosis.
- Failure Black Box: sanitized pre-recovery evidence and state transitions.
- Root Recovery Broker: validated typed recovery capabilities, verification, budgets and anti-loop controls.
- Recovery Memory: causal action-to-state-to-outcome history.
- Gemini Advisor: policy analysis/refinement only while Internet is available; never required on the outage critical path.

DJAEGER must distinguish modem/provider states such as PLMN_VISIBLE_NOT_REGISTERED, REGISTRATION_STUCK, REGISTERED_NO_DATA_SESSION, DATA_SESSION_STALLED, MODEM_RADIO_STACK_SUSPECTED and PROVIDER_SIDE_SUSPECTED. Provider-side conclusions require evidence; failed Internet probes alone are insufficient.

Healthy-state rule: Do not repair a healthy network.

CPU, RAM, DNS, routing, firewall, services, USB and kernel remain supporting evidence when relevant to connectivity, but they are not DJAEGER's primary mission. Features may be added, simplified or removed according to measured impact on Internet availability, recovery accuracy, outage duration and false intervention.

Real incident history is permanent regression ground truth. Production candidates must pass static audit, deterministic state-machine simulation, sanitized historical/synthetic replay, failure tests and safety regression before hardware validation.

See tests/regression/ for the permanent incident regression specification and replay cases.
