#!/bin/bash
# Weekly status digest to Telegram. Config: /etc/home-alert.conf
. /etc/home-alert.conf || exit 1
UP=$(uptime -p | sed 's/^up //')
BAT=$(cat /sys/class/power_supply/BAT0/capacity 2>/dev/null); AC=$(cat /sys/class/power_supply/ADP0/online 2>/dev/null)
HEALTH=$(battery 2>/dev/null | awk -F: '/Health/ {gsub(/^ +/,"",$2); print $2}')
DISK=$(df -h --output=pcent / | tail -1 | tr -d ' ')
NEW=$(ls -t /var/lib/vz/dump/*.zst 2>/dev/null | head -1)
if [ -n "$NEW" ]; then BK="$(basename "$NEW"), $(date -d @"$(stat -c %Y "$NEW")" '+%d.%m %H:%M')"; else BK="none yet"; fi
UPD=$(apt list --upgradable 2>/dev/null | grep -vc '^Listing')
TS=$(tailscale status 2>/dev/null | wc -l)
MSG="📊 Weekly server report
Uptime: $UP
Power: $([ "$AC" = 1 ] && echo "mains" || echo "ON BATTERY"), charge ${BAT}%, battery health: ${HEALTH:-?}
Disk: ${DISK}
Last backup: ${BK}
Pending Proxmox updates: ${UPD}
Tailscale devices: ${TS}"
curl -fsS -m 15 "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
  --data-urlencode "chat_id=${TG_CHAT}" --data-urlencode "text=$MSG" >/dev/null
