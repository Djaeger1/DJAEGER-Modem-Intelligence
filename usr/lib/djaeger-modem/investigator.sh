#!/bin/sh
# Read-only privileged evidence collector. Never executes model supplied commands.
INV_DIR=/root/djaeger-modem/investigator
INV_FILE=$INV_DIR/evidence.txt
mkdir -p "$INV_DIR"; chmod 700 "$INV_DIR" 2>/dev/null
redact(){ sed -E 's/([0-9]{14,20})/[REDACTED_ID]/g; s/([A-Fa-f0-9]{2}:){5}[A-Fa-f0-9]{2}/[REDACTED_MAC]/g; s/(api[_ -]?key|token|password|passwd|secret)[=: ][^ ]+/\1=[REDACTED]/Ig'; }
investigator_collect(){
 T="$INV_FILE.tmp"; : > "$T"
 { echo '[SYSTEM]'; uname -a; uptime; free 2>/dev/null; df -h 2>/dev/null | head -n 20
 echo '[NETWORK]'; ip -br addr 2>/dev/null; ip route 2>/dev/null; ip rule 2>/dev/null
 echo '[WAN_UBUS]'; ubus call network.interface.wan status 2>/dev/null
 echo '[LINK_STATS]'; ip -s link 2>/dev/null
 echo '[CONNTRACK]'; cat /proc/sys/net/netfilter/nf_conntrack_count 2>/dev/null; cat /proc/sys/net/netfilter/nf_conntrack_max 2>/dev/null
 echo '[SERVICES]'; for s in dnsmasq odhcpd firewall; do pidof "$s" >/dev/null 2>&1 && echo "$s=running" || echo "$s=stopped"; done
 command -v pgrep >/dev/null 2>&1 && { pgrep -f openclash >/dev/null 2>&1 && echo openclash=present_running || true; pgrep -f AdGuardHome >/dev/null 2>&1 && echo adguardhome=present_running || true; }
 echo '[USB]'; for d in /sys/bus/usb/devices/*; do [ -f "$d/idVendor" ] || continue; printf '%s vendor=%s product=%s\n' "$(basename "$d")" "$(cat "$d/idVendor" 2>/dev/null)" "$(cat "$d/idProduct" 2>/dev/null)"; done
 echo '[KERNEL_RECENT]'; dmesg 2>/dev/null | tail -n 160 | grep -Ei 'usb|wwan|cdc|eth|net|route|dns|timeout|reset|disconnect|error|fail' | tail -n 100
 echo '[LOG_RECENT]'; logread 2>/dev/null | tail -n 180 | grep -Ei 'netifd|dnsmasq|odhcp|firewall|usb|wan|wwan|error|fail|timeout|restart' | tail -n 120
 echo '[DJAEGER_INCIDENTS]'; tail -n 12 /root/djaeger-modem/incidents.csv 2>/dev/null
 echo '[DJAEGER_RECOVERY]'; tail -n 12 /root/djaeger-modem/recovery-outcomes.csv 2>/dev/null
 } | redact | cut -c1-500 > "$T"
 chmod 600 "$T"; mv "$T" "$INV_FILE"
}
investigator_summary(){ investigator_collect; tr '\n' '|' < "$INV_FILE" | cut -c1-6000; }
