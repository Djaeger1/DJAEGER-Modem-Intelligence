#!/bin/sh
# DJAEGER Whole-System Connectivity Intelligence
SYS_BASE=/root/djaeger-modem; SYS_HEALTH=$SYS_BASE/system-health.csv; SYS_EVENTS=$SYS_BASE/system-events.csv; SYS_STATE=/tmp/djaeger-modem/system-state
mkdir -p "$SYS_BASE"; HEADER='epoch,load100,cpu_count,memavail_pct,conntrack_pct,rootfs_pct,wan_up,default_route,dnsmasq,usb_present,kernel_net_errors,state'; [ -f "$SYS_HEALTH" ] || echo "$HEADER" > "$SYS_HEALTH"; [ -f "$SYS_EVENTS" ] || echo "$HEADER" > "$SYS_EVENTS"
ival(){ case "$1" in ''|*[!0-9]*) echo 0;; *) echo "$1";; esac; }
system_collect(){ LOAD100="$(ival "$(awk '{printf "%d",$1*100}' /proc/loadavg 2>/dev/null)")"; CPU_COUNT="$(ival "$(grep -c '^processor' /proc/cpuinfo 2>/dev/null)")"; [ "$CPU_COUNT" -gt 0 ] || CPU_COUNT=1; MT="$(ival "$(awk '/MemTotal:/{print $2;exit}' /proc/meminfo 2>/dev/null)")"; MA="$(ival "$(awk '/MemAvailable:/{print $2;exit}' /proc/meminfo 2>/dev/null)")"; MEMPCT=0; [ "$MT" -gt 0 ] && MEMPCT=$((MA*100/MT)); CT="$(ival "$(cat /proc/sys/net/netfilter/nf_conntrack_count 2>/dev/null)")"; CTMAX="$(ival "$(cat /proc/sys/net/netfilter/nf_conntrack_max 2>/dev/null)")"; CTPCT=0; [ "$CTMAX" -gt 0 ] && CTPCT=$((CT*100/CTMAX)); ROOTPCT="$(ival "$(df -P / 2>/dev/null | awk 'NR==2{gsub(/%/,"",$5);print $5}')")"; ubus call network.interface.wan status 2>/dev/null | jsonfilter -e '@.up' | grep -qx true && WAN_UP=1 || WAN_UP=0; ip route 2>/dev/null | grep -q '^default ' && ROUTE_OK=1 || ROUTE_OK=0; pidof dnsmasq >/dev/null 2>&1 && DNSMASQ_OK=1 || DNSMASQ_OK=0; [ -d /sys/bus/usb/devices ] && find /sys/bus/usb/devices -maxdepth 2 -name idVendor 2>/dev/null | grep -q . && USB_PRESENT=1 || USB_PRESENT=0; KERR="$(ival "$(dmesg 2>/dev/null | tail -n 80 | grep -Eic 'usb.*(disconnect|reset|error)|net.*(watchdog|timeout)|eth[0-9].*(down|error)' 2>/dev/null)")"; SYS_RISK=0; SYS_REASON=NORMAL; [ "$WAN_UP" = 0 ] && { SYS_RISK=$((SYS_RISK+30)); SYS_REASON=WAN_DOWN; }; [ "$ROUTE_OK" = 0 ] && { SYS_RISK=$((SYS_RISK+30)); SYS_REASON=ROUTING; }; [ "$DNSMASQ_OK" = 0 ] && { SYS_RISK=$((SYS_RISK+20)); SYS_REASON=DNS_SERVICE; }; [ "$CTPCT" -ge 90 ] && { SYS_RISK=$((SYS_RISK+25)); SYS_REASON=CONNTRACK_PRESSURE; }; [ "$MEMPCT" -le 8 ] && { SYS_RISK=$((SYS_RISK+20)); SYS_REASON=MEMORY_PRESSURE; }; [ "$ROOTPCT" -ge 95 ] && { SYS_RISK=$((SYS_RISK+20)); SYS_REASON=STORAGE_PRESSURE; }; [ "$LOAD100" -ge $((CPU_COUNT*300)) ] && { SYS_RISK=$((SYS_RISK+15)); SYS_REASON=LOAD_PRESSURE; }; [ "$KERR" -ge 3 ] && { SYS_RISK=$((SYS_RISK+10)); [ "$SYS_REASON" = NORMAL ] && SYS_REASON=KERNEL_ERRORS; }; [ "$SYS_RISK" -gt 100 ] && SYS_RISK=100; }
system_learn(){ HEALTH_SAMPLE=0; ROW="$(date +%s),$LOAD100,$CPU_COUNT,$MEMPCT,$CTPCT,$ROOTPCT,$WAN_UP,$ROUTE_OK,$DNSMASQ_OK,$USB_PRESENT,$KERR,${CUR:-STARTING}"; if [ "${CUR:-STARTING}" = HEALTHY ] && [ "$SYS_RISK" -le 20 ] && [ "${AI_RISK:-0}" -lt 40 ] 2>/dev/null; then echo "$ROW" >> "$SYS_HEALTH"; HEALTH_SAMPLE=1; else echo "$ROW" >> "$SYS_EVENTS"; fi; for F in "$SYS_HEALTH" "$SYS_EVENTS"; do L="$(wc -l < "$F" 2>/dev/null)"; [ "${L:-0}" -gt 4001 ] && { head -n1 "$F" > "$F.new"; tail -n 4000 "$F" >> "$F.new"; mv "$F.new" "$F"; }; done; cat > "$SYS_STATE.tmp" <<EOF
system_risk=$SYS_RISK
system_reason=$SYS_REASON
load100=$LOAD100
cpu_count=$CPU_COUNT
memavailable_pct=$MEMPCT
conntrack_pct=$CTPCT
rootfs_pct=$ROOTPCT
wan_up=$WAN_UP
default_route=$ROUTE_OK
dnsmasq=$DNSMASQ_OK
usb_present=$USB_PRESENT
kernel_net_errors=$KERR
healthy_sample=$HEALTH_SAMPLE
EOF
 chmod 600 "$SYS_STATE.tmp"; mv "$SYS_STATE.tmp" "$SYS_STATE"; }
