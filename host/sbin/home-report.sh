#!/bin/bash
# Text reports for Telegram. Used by home-bot.sh (commands) and home-digest.sh (daily / weekly digest).
#   home-report.sh status|battery|system|services|ads|check <domain>|backup|daily|weekly|help
# Config: /etc/home-alert.conf. HOME_LANG=ru|en picks the language of the texts.
. /etc/home-alert.conf || exit 1
: "${ADGUARD_CT:=111}" "${ADGUARD_IP:=192.168.1.11}" "${ADGUARD_URL:=http://$ADGUARD_IP}"
: "${MONITOR_CT:=112}" "${MONITOR_IP:=192.168.1.12}" "${ROUTER_IP:=192.168.1.1}"
STATE=/var/lib/home-watchdog
BAT=/sys/class/power_supply/BAT0
MAINS=/sys/class/power_supply/ADP0/online
CONSERVATION=/sys/bus/platform/drivers/ideapad_acpi/VPC2004:00/conservation_mode

L() { if [ "$HOME_LANG" = ru ]; then printf '%s' "$1"; else printf '%s' "$2"; fi; }  # L "русский" "english"
yes_no() { "$@" >/dev/null 2>&1 && printf '✓' || printf '✗'; }

ag() {  # ag /control/... -> JSON from the AdGuard API (fails when no service user is configured)
  [ -n "$ADGUARD_USER" ] || return 1
  curl -fsS -m 8 -K - "${ADGUARD_URL}$1" 2>/dev/null <<<"user = \"${ADGUARD_USER}:${ADGUARD_PASS}\""
}
pc_of() { awk -v b="${1:-0}" -v q="${2:-0}" 'BEGIN { if (q > 0) printf "%.0f", b * 100 / q; else printf "0" }'; }

uptime_h() {
  local s d h m; s=$(cut -d. -f1 /proc/uptime); d=$((s / 86400)); h=$((s % 86400 / 3600)); m=$((s % 3600 / 60))
  if [ "$d" -gt 0 ]; then printf '%s %s %s %s' "$d" "$(L д d)" "$h" "$(L ч h)"
  elif [ "$h" -gt 0 ]; then printf '%s %s %s %s' "$h" "$(L ч h)" "$m" "$(L мин min)"
  else printf '%s %s' "$m" "$(L мин min)"; fi
}
tmax() { local m=0 v z; for z in /sys/class/thermal/thermal_zone*/temp; do v=$(( $(cat "$z" 2>/dev/null || echo 0) / 1000 )); [ "$v" -gt "$m" ] && m=$v; done; echo "$m"; }
disk_used() { df --output=pcent "$1" | tail -1 | tr -dc 0-9; }
lvm_used() { lvs --noheadings -o data_percent pve/data 2>/dev/null | tr -d ' ' | cut -d. -f1; }
ct_disk() { pct exec "$MONITOR_CT" -- df --output=pcent / 2>/dev/null | tail -1 | tr -dc 0-9; }
ct_up() { pct status "$1" 2>/dev/null | grep -q running; }
http_code() { curl -s -m 8 -o /dev/null -w '%{http_code}' -H "Host: $1" "http://${MONITOR_IP}$2"; }

# --- what the watchdog currently holds as a problem
label() {
  case "$1" in
    battery) L "низкий заряд на батарее" "low battery" ;;
    mains) L "нет сетевого питания" "no mains power" ;;
    disk_root) L "диск сервера заполнен" "root disk full" ;;
    disk_lvm) L "хранилище контейнеров заполнено" "container storage full" ;;
    disk_monitor) L "диск контейнера мониторинга заполнен" "monitor container disk full" ;;
    temp) L "перегрев процессора" "CPU overheating" ;;
    mem) L "мало памяти" "low memory" ;;
    ct*) L "контейнер ${1#ct} не запущен" "container ${1#ct} is down" ;;
    docker) L "сервисы Docker" "Docker services" ;;
    kuma) L "Uptime Kuma не отвечает" "Uptime Kuma is down" ;;
    grafana) L "Grafana не отвечает" "Grafana is down" ;;
    prom) L "Prometheus не собирает метрики" "Prometheus is not scraping" ;;
    dns) L "AdGuard не отвечает на DNS" "AdGuard is not answering DNS" ;;
    tailscale) L "Tailscale не работает" "Tailscale is down" ;;
    backup) L "бэкапы устарели" "backups are stale" ;;
    bot) L "Telegram-бот" "Telegram bot" ;;
    *) printf '%s' "$1" ;;
  esac
}
problems() {
  local f
  for f in "$STATE"/*; do
    [ -f "$f" ] && [ "$(cut -d' ' -f1 "$f" 2>/dev/null)" = bad ] && { label "$(basename "$f")"; echo; }
  done
}
verdict() {
  local p; p=$(problems | paste -sd, - | sed 's/,/, /g')
  if [ -n "$p" ]; then echo "⚠️ $(L Проблемы Problems): $p"; else echo "✅ $(L "Всё в порядке" "All good")"; fi
}

# --- power
time_left() {  # " (~1 h 20 min)" while discharging, nothing otherwise
  local st pw now; st=$(cat $BAT/status 2>/dev/null); pw=$(cat $BAT/power_now 2>/dev/null); now=$(cat $BAT/energy_now 2>/dev/null)
  if [ "$st" = Discharging ] && [ "${pw:-0}" -gt 0 ]; then
    awk -v n="$now" -v p="$pw" -v h="$(L ч h)" -v m="$(L мин min)" 'BEGIN { x = int(n / p * 60); printf " (~%d %s %02d %s)", x / 60, h, x % 60, m }'
  fi
}
power_short() {
  local cap ac; cap=$(cat $BAT/capacity 2>/dev/null); ac=$(cat $MAINS 2>/dev/null)
  if [ "$ac" = 1 ]; then echo "🔌 $(L "Питание: сеть, заряд" "Power: mains, charge") ${cap}%"
  else echo "🪫 $(L "НА БАТАРЕЕ, заряд" "ON BATTERY, charge") ${cap}%$(time_left)"; fi
}
battery_text() {
  [ -d "$BAT" ] || { L "Батарея не найдена" "No battery found"; echo; return; }
  local cap st ac full design pw cyc stw
  cap=$(cat $BAT/capacity); st=$(cat $BAT/status); ac=$(cat $MAINS 2>/dev/null)
  full=$(cat $BAT/energy_full); design=$(cat $BAT/energy_full_design); pw=$(cat $BAT/power_now); cyc=$(cat $BAT/cycle_count)
  case "$st" in
    Charging) stw=$(L "заряжается" "charging") ;;
    Discharging) stw=$(L "разряжается" "discharging") ;;
    Full) stw=$(L "полная" "full") ;;
    *) stw=$(L "не заряжается" "not charging") ;;
  esac
  echo "🔋 $(L Заряд Charge): ${cap}% ($stw)$(time_left)"
  echo "🔌 $(L Зарядка Charger): $([ "$ac" = 1 ] && L "подключена" "connected" || L "ОТКЛЮЧЕНА" "NOT connected")"
  awk -v p="$pw" -v l="$(L "Потребление" "Power draw")" 'BEGIN { printf "⚡ %s: %.1f W\n", l, p / 1000000 }'
  awk -v f="$full" -v d="$design" -v l="$(L "Здоровье батареи" "Battery health")" -v t="$(L "от начальной ёмкости" "of original capacity")" 'BEGIN { printf "❤️ %s: %.0f%% %s\n", l, f / d * 100, t }'
  echo "🔁 $(L "Циклов зарядки" "Charge cycles"): $cyc"
  echo "🛡 $(L "Бережный режим" "Conservation mode"): $([ "$(cat $CONSERVATION 2>/dev/null)" = 1 ] && L "включён (держит ~60%)" "on (holds ~60%)" || L "выключен" "off")"
  echo "⏻ $(L "Автовыключение на батарее" "Auto-shutdown on battery"): 10% ($(systemctl is-active battery-guard.timer))"
}

# --- system and services
system_text() {
  local mt ma
  mt=$(awk '/MemTotal/ {printf "%.1f", $2 / 1048576}' /proc/meminfo); ma=$(awk '/MemAvailable/ {printf "%.1f", $2 / 1048576}' /proc/meminfo)
  echo "⏱ $(L Работает Uptime): $(uptime_h)"
  echo "⚙️ $(L Нагрузка Load): $(cut -d' ' -f1-3 /proc/loadavg)"
  echo "🌡 $(L Процессор CPU): $(tmax)°C"
  echo "🧠 $(L Память Memory): $(L "свободно ${ma} из ${mt} ГБ" "${ma} of ${mt} GB free")"
  echo "💽 $(L Диски Disks): / $(disk_used /)% · local-lvm $(lvm_used)% · $(L мониторинг monitor) $(ct_disk)%"
}
services_text() {
  local run n unh kc gc ts
  echo "🧩 $(L Контейнеры Containers): AdGuard $(yes_no ct_up "$ADGUARD_CT") · $(L Мониторинг Monitor) $(yes_no ct_up "$MONITOR_CT")"
  run=$(pct exec "$MONITOR_CT" -- docker ps --format '{{.Names}} {{.Status}}' 2>/dev/null)
  n=$(grep -c . <<<"$run"); unh=$(grep -c unhealthy <<<"$run")
  echo "🐳 Docker: $(L "работает $n из 5, с ошибками $unh" "$n of 5 running, $unh unhealthy")"
  kc=$(http_code status.home /); gc=$(http_code grafana.home /api/health)
  echo "📈 Uptime Kuma $([[ $kc =~ ^(200|302)$ ]] && echo ✓ || echo ✗) · Grafana $([ "$gc" = 200 ] && echo ✓ || echo ✗)"
  ts=$(tailscale status --json 2>/dev/null | jq -r .BackendState 2>/dev/null)
  echo "🌐 $(L Интернет Internet) $(yes_no ping -c1 -W2 1.1.1.1) · $(L Роутер Router) $(yes_no ping -c1 -W2 "$ROUTER_IP") · DNS $(yes_no timeout 5 nslookup example.com "$ADGUARD_IP") · Tailscale $([ "$ts" = Running ] && echo ✓ || echo ✗)"
}

# --- ad blocking (AdGuard API)
ads_stats() {  # today_q today_b yesterday_q yesterday_b week_q week_b days_kept
  jq -r '. as $s | ($s.time_units == "days") as $d
    | [ (if $d then ($s.dns_queries | last) else ($s.dns_queries | add) end),
        (if $d then ($s.blocked_filtering | last) else ($s.blocked_filtering | add) end),
        (if $d then ($s.dns_queries[-2] // 0) else ($s.dns_queries | add) end),
        (if $d then ($s.blocked_filtering[-2] // 0) else ($s.blocked_filtering | add) end),
        ($s.dns_queries[-7:] | add), ($s.blocked_filtering[-7:] | add), ($s.dns_queries | length) ] | @tsv' <<<"$1"
}
ads_line() {  # ads_line today|yesterday|week
  local S tq tb yq yb wq wb nd q b lbl
  S=$(ag /control/stats) && [ -n "$S" ] || { echo "🛡 $(L "Реклама: нет данных от AdGuard" "Ads: no data from AdGuard")"; return; }
  read -r tq tb yq yb wq wb nd <<<"$(ads_stats "$S")"
  case "$1" in
    yesterday) q=$yq; b=$yb; lbl=$(L "Реклама вчера" "Ads yesterday") ;;
    week) q=$wq; b=$wb; lbl=$(L "Реклама за 7 дней" "Ads, 7 days") ;;
    *) q=$tq; b=$tb; lbl=$(L "Реклама сегодня" "Ads today") ;;
  esac
  if [ "${q:-0}" -gt 0 ]; then echo "🛡 $lbl: $(L "заблокировано $b из $q запросов" "blocked $b of $q queries") ($(pc_of "$b" "$q")%)"
  else echo "🛡 $lbl: $(L "нет данных" "no data")"; fi
}
top_blocked() { ag /control/stats | jq -r '.top_blocked_domains[:5][] | to_entries[0] | "  \(.key) — \(.value)"'; }
ads_text() {
  local st F
  ag /control/stats >/dev/null || { ads_line today; return; }
  st=$(ag /control/status | jq -r 'if .protection_enabled then "on" else "off" end')
  echo "🛡 AdGuard: $([ "$st" = on ] && L "защита включена" "protection on" || L "ЗАЩИТА ВЫКЛЮЧЕНА" "protection OFF")"
  ads_line today; ads_line yesterday; ads_line week
  F=$(ag /control/filtering/status | jq -r '[(.filters // [])[] | select(.enabled)] | "\(length) \(map(.rules_count) | add)"')
  echo "📚 $(L "Подключено списков" "Lists enabled"): ${F% *}, $(L "правил" "rules"): ${F#* }"
  echo "🔝 $(L "Чаще всего блокируется" "Most blocked"):"; top_blocked
}
check_text() {
  local d=${1,,} r reason rule fid fname ans
  d=${d#*://}; d=${d%%/*}
  [[ $d =~ ^[a-z0-9]([a-z0-9._-]{0,251}[a-z0-9])?$ ]] || { L "Пример: /check doubleclick.net" "Example: /check doubleclick.net"; echo; return; }
  r=$(ag "/control/filtering/check_host?name=$d") || { L "AdGuard API недоступен" "AdGuard API unavailable"; echo; return; }
  reason=$(jq -r .reason <<<"$r"); rule=$(jq -r '.rule // ""' <<<"$r"); fid=$(jq -r '.filter_id // 0' <<<"$r")
  fname=$(ag /control/filtering/status | jq -r --argjson id "${fid:-0}" '(.filters // [])[] | select(.id == $id) | .name' 2>/dev/null)
  ans=$(dig +short +time=3 +tries=1 @"$ADGUARD_IP" "$d" A 2>/dev/null | head -3 | paste -sd' ')
  case "$reason" in
    NotFilteredNotFound) echo "✅ $d — $(L "не заблокирован" "not blocked")" ;;
    NotFilteredWhiteList) echo "✅ $d — $(L "разрешён правилом" "allowed by a rule")" ;;
    Filtered*) echo "🚫 $d — $(L "ЗАБЛОКИРОВАН" "BLOCKED") ($reason)" ;;
    *) echo "ℹ️ $d — $reason" ;;
  esac
  [ -n "$rule" ] && echo "$(L Правило Rule): $rule"
  [ -n "$fname" ] && echo "$(L Список List): $fname"
  echo "$(L "Ответ AdGuard" "AdGuard answer"): ${ans:-—}"
}

# --- backups
backup_text() {
  local list f
  list=$(ls -t /var/lib/vz/dump/*.zst 2>/dev/null | head -6)
  [ -n "$list" ] || { echo "💾 $(L "Бэкапов пока нет (по расписанию: воскресенье 03:30)" "No backups yet (scheduled: Sunday 03:30)")"; return; }
  echo "💾 $(L "Последние бэкапы" "Latest backups"):"
  while read -r f; do
    echo "  CT $(basename "$f" | sed -E 's/^vzdump-lxc-([0-9]+)-.*/\1/') · $(date -d @"$(stat -c %Y "$f")" '+%d.%m %H:%M') · $(du -h "$f" | cut -f1)"
  done <<<"$list"
}
backup_short() {
  local new; new=$(ls -t /var/lib/vz/dump/*.zst 2>/dev/null | head -1)
  if [ -n "$new" ]; then echo "💾 $(L "Бэкап" "Backup"): $(( ($(date +%s) - $(stat -c %Y "$new")) / 86400 )) $(L "дн. назад" "days ago")"
  else echo "💾 $(L "Бэкап: пока нет" "Backup: none yet")"; fi
}

# --- composed reports
help_text() {
  if [ "$HOME_LANG" = ru ]; then cat <<'EOF'
🤖 Команды:
/status — общая сводка
/battery — батарея подробно
/system — нагрузка, память, диски, температура
/services — контейнеры, сервисы, сеть
/ads — статистика блокировки рекламы
/check сайт — заблокирован ли сайт и каким списком
/backup — последние бэкапы
/report — недельный отчёт сейчас

Сам пишу: сразу при проблемах, кратко каждый день в 09:00, по воскресеньям недельный отчёт.
EOF
  else cat <<'EOF'
🤖 Commands:
/status — overall summary
/battery — battery details
/system — load, memory, disks, temperature
/services — containers, services, network
/ads — ad-blocking statistics
/check site — is a site blocked, and by which list
/backup — latest backups
/report — weekly report now

Automatic: instantly on problems, a short report every day at 09:00, the weekly report on Sundays.
EOF
  fi
}
status_text() { verdict; power_short; system_text; services_text; ads_line today; backup_short; }
daily_text() {
  echo "☀️ $(L "Краткий отчёт" "Daily report"), $(date '+%d.%m')"
  verdict; power_short
  echo "🖥 $(uptime_h) · CPU $(tmax)°C · $(L "диск" "disk") $(disk_used /)%"
  ads_line yesterday; backup_short
}
weekly_text() {
  echo "📊 $(L "Недельный отчёт" "Weekly report"), $(date '+%d.%m')"
  verdict; battery_text; system_text; ads_line week; top_blocked; backup_text
  echo "🔄 $(L "Обновлений Proxmox" "Pending Proxmox updates"): $(apt list --upgradable 2>/dev/null | grep -vc '^Listing')"
  echo "🧷 $(L "Устройств в Tailscale" "Tailscale devices"): $(tailscale status 2>/dev/null | wc -l)"
}

case "$1" in
  status) status_text ;;
  battery) battery_text ;;
  system) system_text ;;
  services) services_text ;;
  ads) ads_text ;;
  check) check_text "$2" ;;
  backup) backup_text ;;
  daily) daily_text ;;
  weekly) weekly_text ;;
  help) help_text ;;
  *) echo "usage: $0 status|battery|system|services|ads|check <domain>|backup|daily|weekly|help" >&2; exit 1 ;;
esac
