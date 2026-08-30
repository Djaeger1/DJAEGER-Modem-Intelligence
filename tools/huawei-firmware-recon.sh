#!/bin/sh
# DJAEGER Huawei Firmware Recon Dump v1
# READ-ONLY: no POST, reboot, config write, AT command, flash access or mode switching.
set -u
MODEM="${1:-192.168.8.1}"
BASE="http://$MODEM"
TS="$(date +%Y%m%d-%H%M%S)"
OUT="/tmp/DJAEGER-Huawei-Recon-$TS"
ARCHIVE="/tmp/DJAEGER-Huawei-Recon-$TS.tar.gz"
mkdir -p "$OUT/api"
umask 077

redact(){
  sed -E \
    -e 's#<(Imei|IMEI|Imsi|IMSI|Iccid|ICCID|SerialNumber|Serial|MacAddress|MACAddress|WifiMac|WanMac)>[^<]*</#<\1>REDACTED</#g' \
    -e 's#([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}#REDACTED_MAC#g' \
    -e 's#\b[0-9]{14,20}\b#REDACTED_ID#g'
}

safe_cmd(){
  name="$1"; shift
  { echo "### $*"; "$@" 2>&1 || true; } | redact > "$OUT/$name.txt"
}

api_get(){
  ep="$1"; name="$(echo "$ep" | tr '/' '_' | sed 's/^_//')"
  # Some HiLink firmware accepts GET without token; others need session cookie/token.
  body="$(curl -fsS --connect-timeout 2 --max-time 5 "$BASE/$ep" 2>/dev/null || true)"
  if [ -z "$body" ] || echo "$body" | grep -q '<code>125002</code>'; then
    st="$(curl -fsS --connect-timeout 2 --max-time 5 "$BASE/api/webserver/SesTokInfo" 2>/dev/null || true)"
    sid="$(echo "$st" | sed -n 's:.*<SesInfo>\([^<]*\)</SesInfo>.*:\1:p' | head -n1)"
    tok="$(echo "$st" | sed -n 's:.*<TokInfo>\([^<]*\)</TokInfo>.*:\1:p' | head -n1)"
    [ -n "$sid" ] && body="$(curl -fsS --connect-timeout 2 --max-time 5 -H "Cookie: $sid" -H "__RequestVerificationToken: $tok" "$BASE/$ep" 2>/dev/null || true)"
  fi
  printf '%s\n' "$body" | redact > "$OUT/api/$name.xml"
}

{
 echo "DJAEGER Huawei Firmware Recon Dump v1"
 echo "timestamp=$(date -Iseconds 2>/dev/null || date)"
 echo "mode=READ_ONLY"
 echo "modem=$MODEM"
 echo "hostname=$(hostname 2>/dev/null)"
 echo "kernel=$(uname -r 2>/dev/null)"
 echo "arch=$(uname -m 2>/dev/null)"
} > "$OUT/manifest.txt"

# HiLink read-only reconnaissance endpoints. Unsupported endpoints are preserved as empty/error evidence.
for ep in \
 api/device/information \
 api/device/basic_information \
 api/device/signal \
 api/monitoring/status \
 api/monitoring/traffic-statistics \
 api/net/current-plmn \
 api/net/net-mode \
 api/net/net-mode-list \
 api/dialup/connection \
 api/dialup/profiles \
 api/pin/status \
 api/webserver/publickey \
 api/webserver/SesTokInfo
do
  api_get "$ep"
done

safe_cmd usb_devices sh -c 'cat /sys/kernel/debug/usb/devices 2>/dev/null || true'
safe_cmd usb_sysfs sh -c 'for d in /sys/bus/usb/devices/*; do [ -f "$d/idVendor" ] || continue; echo "--- $d"; for f in idVendor idProduct manufacturer product bcdDevice bDeviceClass bDeviceSubClass bDeviceProtocol; do [ -f "$d/$f" ] && echo "$f=$(cat "$d/$f")"; done; done'
safe_cmd interfaces ip -details link show
safe_cmd addresses ip address show
safe_cmd routes ip route show table all
safe_cmd rules ip rule show
safe_cmd neighbors ip neigh show
safe_cmd modules lsmod
safe_cmd processes sh -c 'ps w | grep -Ei "usb|cdc|rndis|qmi|mbim|modem|hilink" | grep -v grep || true'
safe_cmd kernel_modem sh -c 'dmesg | grep -Ei "usb|cdc_ether|rndis|qmi|mbim|modem|huawei" | tail -n 400'
safe_cmd network_uci sh -c 'uci show network 2>/dev/null || true'
safe_cmd ubus_interfaces sh -c 'ubus call network.interface dump 2>/dev/null || true'
safe_cmd ports sh -c 'ss -lntup 2>/dev/null || netstat -lntup 2>/dev/null || true'

# Never include cookies/tokens in output.
find "$OUT" -type f -exec sed -i -E \
  -e 's#<SesInfo>[^<]*</SesInfo>#<SesInfo>REDACTED_SESSION</SesInfo>#g' \
  -e 's#<TokInfo>[^<]*</TokInfo>#<TokInfo>REDACTED_TOKEN</TokInfo>#g' {} \; 2>/dev/null || true

# Final identity scrub across all text files.
for f in $(find "$OUT" -type f); do
  tmp="$f.tmp"; redact < "$f" > "$tmp" && mv "$tmp" "$f"
done

tar -czf "$ARCHIVE" -C /tmp "$(basename "$OUT")"
chmod 600 "$ARCHIVE"
echo "DJAEGER Huawei Firmware Recon selesai."
echo "READ-ONLY: tidak ada reboot/write/flash operation."
echo "File: $ARCHIVE"
