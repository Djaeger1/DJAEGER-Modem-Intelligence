#!/bin/sh
# DJAEGER Huawei E3276 Deep Recon v2
# STRICTLY READ-ONLY. No POST, AT commands, usb_modeswitch, debug/project mode, reboot, NV/flash write.
set -u
MODEM="${1:-192.168.8.1}"; BASE="http://$MODEM"; TS="$(date +%Y%m%d-%H%M%S)"
OUT="/tmp/DJAEGER-Huawei-DeepRecon-$TS"; ARCHIVE="/tmp/DJAEGER-Huawei-DeepRecon-$TS.tar.gz"
umask 077; mkdir -p "$OUT/api" "$OUT/usb" "$OUT/web"
redact(){ sed -E -e 's#<(Imei|IMEI|Imsi|IMSI|Iccid|ICCID|SerialNumber|Serial|MacAddress|MACAddress|WifiMac|WanMac)>[^<]*</#<\1>REDACTED</#g' -e 's#([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}#REDACTED_MAC#g' -e 's#\b[0-9]{14,20}\b#REDACTED_ID#g' -e 's#<SesInfo>[^<]*</SesInfo>#<SesInfo>REDACTED_SESSION</SesInfo>#g' -e 's#<TokInfo>[^<]*</TokInfo>#<TokInfo>REDACTED_TOKEN</TokInfo>#g'; }
session(){ ST="$(curl -fsS --connect-timeout 2 --max-time 4 "$BASE/api/webserver/SesTokInfo" 2>/dev/null || true)"; SID="$(echo "$ST"|sed -n 's:.*<SesInfo>\([^<]*\)</SesInfo>.*:\1:p'|head -n1)"; TOK="$(echo "$ST"|sed -n 's:.*<TokInfo>\([^<]*\)</TokInfo>.*:\1:p'|head -n1)"; }
get(){ ep="$1"; n="$(echo "$ep"|tr '/' '_')"; session; if [ -n "${SID:-}" ]; then B="$(curl -fsS --connect-timeout 2 --max-time 5 -H "Cookie: $SID" -H "__RequestVerificationToken: ${TOK:-}" -H 'X-Requested-With: XMLHttpRequest' "$BASE/$ep" 2>/dev/null || true)"; else B="$(curl -fsS --connect-timeout 2 --max-time 5 "$BASE/$ep" 2>/dev/null || true)"; fi; printf '%s\n' "$B"|redact > "$OUT/api/$n.xml"; }
cmd(){ n="$1"; shift; { echo "### $*"; "$@" 2>&1 || true; }|redact > "$OUT/$n.txt"; }
cat > "$OUT/README.txt" <<EOF
DJAEGER Huawei Deep Recon v2
Target: $MODEM
Timestamp: $(date)
Safety: READ ONLY. This collector intentionally does NOT enable debug/project mode, send AT commands, switch USB modes, reboot, modify NV, or access flash for writing.
EOF
# Known/read-only HiLink surface plus registration/data-session candidates. Unsupported endpoints are useful evidence.
for ep in api/device/information api/device/basic_information api/device/signal api/monitoring/status api/monitoring/traffic-statistics api/monitoring/check-notifications api/net/current-plmn api/net/net-mode api/net/net-mode-list api/net/register api/net/plmn-list api/dialup/connection api/dialup/profiles api/dialup/mobile-dataswitch api/pin/status api/sms/sms-count api/webserver/SesTokInfo api/webserver/publickey; do get "$ep"; done
# WebUI fingerprint only; GET requests.
for p in / /html/home.html /config/global/config.xml /config/deviceinformation/config.xml; do n="$(echo "$p"|sed 's#[/.]#_#g')"; curl -fsS --connect-timeout 2 --max-time 5 "$BASE$p" 2>/dev/null | head -c 262144 | redact > "$OUT/web/$n.txt" || true; done
cmd usb_lsusb sh -c 'lsusb 2>/dev/null || true; lsusb -t 2>/dev/null || true'
cmd usb_sysfs sh -c 'for d in /sys/bus/usb/devices/*; do [ -r "$d/idVendor" ] || continue; echo "--- $d"; for f in idVendor idProduct bcdDevice bDeviceClass bDeviceSubClass bDeviceProtocol manufacturer product; do [ -r "$d/$f" ] && echo "$f=$(cat "$d/$f")"; done; for i in "$d":*; do [ -d "$i" ] || continue; echo "interface=$i"; for f in bInterfaceClass bInterfaceSubClass bInterfaceProtocol interface; do [ -r "$i/$f" ] && echo "$f=$(cat "$i/$f")"; done; done; done'
cmd tty_inventory sh -c 'ls -l /dev/ttyUSB* /dev/ttyACM* /dev/cdc-wdm* 2>/dev/null || true; for d in /sys/class/tty/ttyUSB* /sys/class/tty/ttyACM*; do [ -e "$d" ] && readlink -f "$d/device"; done'
cmd net_inventory sh -c 'ip -details link; ip addr; ip route show table all; ip rule; ip neigh'
cmd drivers sh -c 'lsmod; find /sys/bus/usb/drivers -maxdepth 2 -type l 2>/dev/null | head -n 300'
cmd kernel_huawei sh -c 'dmesg | grep -Ei "12d1|Huawei|usb|cdc_ether|option|ttyUSB|wwan|qmi|mbim" | tail -n 800'
cmd openwrt_network sh -c 'uci show network 2>/dev/null; ubus call network.interface dump 2>/dev/null'
cmd packages sh -c 'opkg list-installed 2>/dev/null | grep -Ei "usb|modem|serial|qmi|mbim|cdc|huawei" || true'
# Evidence classifier, no state changes.
{
 echo "=== DJAEGER DEEP RECON SUMMARY ==="
 V="$(cat /sys/bus/usb/devices/*/idVendor 2>/dev/null|grep -c '^12d1$' || true)"; echo "huawei_usb_nodes=$V"
 ls /dev/ttyUSB* >/dev/null 2>&1 && echo 'serial_interface_visible=YES' || echo 'serial_interface_visible=NO'
 ls /dev/cdc-wdm* >/dev/null 2>&1 && echo 'wdm_interface_visible=YES' || echo 'wdm_interface_visible=NO'
 grep -Rqs '<FullName>\|<ShortName>\|<Numeric>' "$OUT/api" && echo 'plmn_information=VISIBLE' || echo 'plmn_information=NOT_CONFIRMED'
 grep -Rqs '<WanIPAddress>[^<]' "$OUT/api" && echo 'wan_state=EXPOSED_BY_API' || echo 'wan_state=NOT_CONFIRMED'
 echo 'debug_mode_changed=NO'; echo 'usb_mode_changed=NO'; echo 'at_commands_sent=NO'; echo 'flash_write=NO'
} > "$OUT/summary.txt"
# final scrub
find "$OUT" -type f | while read -r f; do t="$f.tmp"; redact < "$f" > "$t" && mv "$t" "$f"; done
tar -czf "$ARCHIVE" -C /tmp "$(basename "$OUT")"; chmod 600 "$ARCHIVE"
echo 'DJAEGER Huawei Deep Recon v2 selesai.'
echo "File: $ARCHIVE"
echo 'Tidak ada perubahan pada firmware/modem.'
