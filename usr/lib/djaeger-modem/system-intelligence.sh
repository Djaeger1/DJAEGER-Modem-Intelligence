#!/bin/sh
# DJAEGER Whole-System Connectivity Intelligence
SYS_BASE=/root/djaeger-modem
SYS_MEMORY=$SYS_BASE/system-health.csv
SYS_STATE=/tmp/djaeger-modem/system-state
mkdir -p "$SYS_BASE"
[ -f "$SYS_MEMORY" ] || echo 'epoch,health,load100,memavail_kb,conntrack_pct,wan_up,default_route,dnsmasq,usb_present,kernel_net_errors' > "$SYS_MEMORY"
ival(){ case "$1" in ''|*[!0-9]*) echo 0;; *) echo "$1";; esac; }
system_observe(){
 LOAD100="$(awk '{printf "%d",$1*100}' /proc/loadavg 2>/dev/null)"; LOAD100="$(ival "$LOAD100")"
 MEMAVAIL="$(awk '/MemAvailable:/{print $2;exit}' /proc/meminfo 2>/dev/null)"; MEMAVAIL="$(ival "$MEMAVAIL")"
 CT="$(cat /proc/sys/net/netfilter/nf_conntrack_count 2>/dev/null || echo 0)"; CTMAX="$(cat /proc/sys/net/netfilter/nf_conntrack_max 2>/dev/null || echo 0)"; CT="$(ival "$CT")"; CTMAX="$(ival "$CTMAX")"; CTPCT=0; [ "$CTMAX" -gt 0 ] && CTPCT=$((CT*100/CTMAX))
 if ubus call network.interface.wan status 2>/dev/null | jsonfilter -e '@.up' | grep -qx true; then WAN_UP=1; else WAN_UP=0; fi
 ip route 2>/dev/null | grep -q '^default ' && ROUTE_OK=1 || ROUTE_OK=0
 pidof dnsmasq >/dev/null 2>&1 && DNSMASQ_OK=1 || DNSMASQ_OK=0
 [ -d /sys/bus/usb/devices ] && find /sys/bus/usb/devices -maxdepth 2 -name idVendor 2>/dev/null | grep -q . && USB_PRESENT=1 || USB_PRESENT=0
 KERR="$(dmesg 2>/dev/null | tail -n 120 | grep -Eic 'usb.*(disconnect|reset|error)|net.*(watchdog|timeout)|eth[0-9].*(down|error)' 2>/dev/null)"; KERR="$(ival "$KERR")"
 SYS_RISK=0; SYS_REASON=NORMAL
 [ "$WAN_UP" = 0 ] && { SYS_RISK=$((SYS_RISK+30)); SYS_REASON=WAN_DOWN; }
 [ "$ROUTE_OK" = 0 ] && { SYS_RISK=$((SYS_RISK+30)); SYS_REASON=ROUTE_MISSING; }
 [ "$DNSMASQ_OK" = 0 ] && { SYS_RISK=$((SYS_RISK+20)); SYS_REASON=DNS_SERVICE_DOWN; }
 [ "$CTPCT" -ge 90 ] 2>/dev/null && { SYS_RISK=$((SYS_RISK+25)); SYS_REASON=CONNTRACK_PRESSURE; }
 [ "$KERR" -ge 3 ] 2>/dev/null && { SYS_RISK=$((SYS_RISK+20)); SYS_REASON=KERNEL_OR_USB_ERRORS; }
 [ "$SYS_RISK" -gt 100 ] && SYS_RISK=100
 if [ "${CUR:-STARTING}" = HEALTHY ] && [ "$SYS_RISK" -le 20 ]; then HEALTH_SAMPLE=1; else HEALTH_SAMPLE=0; fi
 printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' "$(date +%s)" "$HEALTH_SAMPLE" "$LOAD100" "$MEMAVAIL" "$CTPCT" "$WAN_UP" "$ROUTE_OK" "$DNSMASQ_OK" "$USB_PRESENT" "$KERR" >> "$SYS_MEMORY"
 L="$(wc -l < "$SYS_MEMORY" 2>/dev/null)"; [ "${L:-0}" -gt 4001 ] && { head -n1 "$SYS_MEMORY" > "$SYS_MEMORY.new"; tail -n 4000 "$SYS_MEMORY" >> "$SYS_MEMORY.new"; mv "$SYS_MEMORY.new" "$SYS_MEMORY"; }
 cat > "$SYS_STATE.tmp" <<EOF
system_risk=$SYS_RISK
system_reason=$SYS_REASON
load100=$LOAD100
memavailable_kb=$MEMAVAIL
conntrack_pct=$CTPCT
wan_up=$WAN_UP
default_route=$ROUTE_OK
dnsmasq=$DNSMASQ_OK
usb_present=$USB_PRESENT
kernel_net_errors=$KERR
healthy_sample=$HEALTH_SAMPLE
EOF
 chmod 600 "$SYS_STATE.tmp"; mv "$SYS_STATE.tmp" "$SYS_STATE"
}
