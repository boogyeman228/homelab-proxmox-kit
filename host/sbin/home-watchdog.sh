#!/bin/bash
# Home server watchdog. Every 5 minutes it checks the Proxmox host and the monitoring stack
# and sends a Telegram message only when a state changes (plus a reminder every 6 h while a
# problem lasts). Independent from Uptime Kuma, so it still works if Kuma is the thing that broke.
#
# Config: /etc/home-alert.conf (TG_TOKEN, TG_CHAT, ADGUARD_CT, ADGUARD_IP, MONITOR_CT, MONITOR_IP)
# Optional external dead-man switch: put a healthchecks.io-style ping URL in /etc/healthchecks-url
STATE=/var/lib/home-watchdog
mkdir -p "$STATE"
. /etc/home-alert.conf || exit 1
: "${ADGUARD_CT:=111}" "${ADGUARD_IP:=192.168.1.11}" "${MONITOR_CT:=112}" "${MONITOR_IP:=192.168.1.12}"
NOW=$(date +%s)

tg() {  # tg "text" -> 0 if Telegram accepted the message
  curl -fsS -m 15 "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${TG_CHAT}" --data-urlencode "text=$1" >/dev/null 2>&1
}

# check KEY ok|bad "text"
# State is only saved after Telegram accepted the message, so alerts raised during an
# internet outage are delivered once the connection is back.
check() {
  local key=$1 st=$2 msg=$3 f="$STATE/$1" prev last
  prev=$(cut -d' ' -f1 "$f" 2>/dev/null); last=$(cut -d' ' -f2 "$f" 2>/dev/null)
  if [ "$st" = bad ]; then
    if [ "$prev" != bad ]; then
      tg "⚠️ $msg" && echo "bad $NOW" > "$f"
    elif [ $((NOW - ${last:-0})) -ge 21600 ]; then
      tg "⚠️ (still) $msg" && echo "bad $NOW" > "$f"
    fi
  elif [ "$prev" = bad ]; then
    tg "✅ Recovered: $msg" && echo "ok $NOW" > "$f"
  fi
}

# --- reboot detection
BID=$(cat /proc/sys/kernel/random/boot_id)
if [ -f "$STATE/boot_id" ] && [ "$(cat "$STATE/boot_id")" != "$BID" ]; then
  tg "🔄 Server rebooted (or powered back on). Now: $(date '+%d.%m %H:%M')" && echo "$BID" > "$STATE/boot_id"
else
  echo "$BID" > "$STATE/boot_id"
fi

# --- power / battery (laptop used as a server)
AC=$(cat /sys/class/power_supply/ADP0/online 2>/dev/null); CAP=$(cat /sys/class/power_supply/BAT0/capacity 2>/dev/null)
if [ "$AC" = 0 ] && [ "${CAP:-100}" -le 30 ]; then check battery bad "Server is on battery, charge ${CAP}% (it shuts down cleanly at 10%)"
else check battery ok "battery charge / power OK"; fi
if [ "$AC" = 0 ]; then check mains bad "No mains power, running on battery (${CAP}%)"; else check mains ok "mains power is back"; fi

# --- disks
R=$(df --output=pcent / | tail -1 | tr -dc 0-9)
[ "${R:-0}" -ge 85 ] && check disk_root bad "Root disk is ${R}% full" || check disk_root ok "root disk (${R}%)"
T=$(lvs --noheadings -o data_percent pve/data 2>/dev/null | tr -d ' ' | cut -d. -f1)
if [ -n "$T" ]; then [ "$T" -ge 85 ] && check disk_lvm bad "Container storage (local-lvm) is ${T}% full" || check disk_lvm ok "container storage (${T}%)"; fi
C=$(pct exec "$MONITOR_CT" -- df --output=pcent / 2>/dev/null | tail -1 | tr -dc 0-9)
if [ -n "$C" ]; then [ "$C" -ge 85 ] && check disk_monitor bad "Disk of the monitor container is ${C}% full" || check disk_monitor ok "monitor container disk (${C}%)"; fi

# --- temperature, memory
TMAX=0; for z in /sys/class/thermal/thermal_zone*/temp; do v=$(( $(cat "$z" 2>/dev/null || echo 0) / 1000 )); [ "$v" -gt "$TMAX" ] && TMAX=$v; done
[ "$TMAX" -ge 85 ] && check temp bad "CPU is overheating: ${TMAX}°C" || check temp ok "temperature (${TMAX}°C)"
MA=$(awk '/MemAvailable/ {print int($2/1024)}' /proc/meminfo)
[ "${MA:-9999}" -lt 300 ] && check mem bad "Low memory: ${MA} MB available" || check mem ok "memory (${MA} MB available)"

# --- containers and the monitoring stack
for id in "$ADGUARD_CT" "$MONITOR_CT"; do
  if pct status "$id" 2>/dev/null | grep -q running; then check ct$id ok "container $id is running"; else check ct$id bad "Container $id is not running"; fi
done
if pct status "$MONITOR_CT" 2>/dev/null | grep -q running; then
  RUN=$(pct exec "$MONITOR_CT" -- docker ps --format '{{.Names}}' 2>/dev/null); MISS=""
  for n in stack-uptime-kuma-1 stack-grafana-1 stack-prometheus-1 stack-homepage-1 stack-caddy-1; do echo "$RUN" | grep -qx "$n" || MISS="$MISS $n"; done
  UNH=$(pct exec "$MONITOR_CT" -- docker ps --filter health=unhealthy --format '{{.Names}}' 2>/dev/null)
  if [ -n "$MISS$UNH" ]; then check docker bad "Not running / unhealthy in the monitor container:${MISS} ${UNH}"; else check docker ok "monitor stack services"; fi
  code() { curl -s -m 8 -o /dev/null -w '%{http_code}' -H "Host: $1" "http://${MONITOR_IP}$2"; }
  case "$(code status.home /)" in 200|302) check kuma ok "Uptime Kuma";; *) check kuma bad "Uptime Kuma does not answer (status.home)";; esac
  [ "$(code grafana.home /api/health)" = 200 ] && check grafana ok "Grafana" || check grafana bad "Grafana does not answer (grafana.home)"
  PU=$(pct exec "$MONITOR_CT" -- docker exec stack-prometheus-1 wget -qO- 'http://localhost:9090/api/v1/query?query=up' 2>/dev/null)
  echo "$PU" | grep -q '"1"\]' && check prom ok "Prometheus is scraping the host" || check prom bad "Prometheus is not scraping the host"
fi

# --- DNS (AdGuard) and Tailscale
if timeout 5 nslookup example.com "$ADGUARD_IP" >/dev/null 2>&1; then check dns ok "AdGuard answers DNS queries"; else check dns bad "AdGuard ($ADGUARD_IP) does not answer DNS queries"; fi
TS=$(tailscale status --json 2>/dev/null | grep -o '"BackendState": *"[A-Za-z]*"' | head -1 | grep -o '[A-Za-z]*"$' | tr -d '"')
[ "$TS" = Running ] && check tailscale ok "Tailscale" || check tailscale bad "Tailscale is not running (${TS:-no answer})"

# --- backups: the newest dump must be younger than 9 days (grace period after install)
[ -f "$STATE/installed" ] || echo "$NOW" > "$STATE/installed"
NEW=$(ls -t /var/lib/vz/dump/*.zst /var/lib/vz/dump/*.lzo /var/lib/vz/dump/*.gz 2>/dev/null | head -1)
if [ -n "$NEW" ]; then AGE=$(( (NOW - $(stat -c %Y "$NEW")) / 86400 )); else AGE=$(( (NOW - $(cat "$STATE/installed")) / 86400 )); fi
[ "$AGE" -ge 9 ] && check backup bad "Container backups are ${AGE} days old (should be weekly)" || check backup ok "backups are fresh"

# --- external dead-man switch (optional)
[ -s /etc/healthchecks-url ] && curl -fsS -m 10 "$(head -n1 /etc/healthchecks-url)" >/dev/null 2>&1
exit 0
