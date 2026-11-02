#!/bin/bash
# Telegram command bot. Long-polls getUpdates (outbound HTTPS only, so it works behind CGNAT) and answers
# commands such as /status or /battery. Only the chat configured in /etc/home-alert.conf is answered;
# messages from any other chat are ignored. The texts come from home-report.sh.
STATE=/var/lib/home-watchdog
mkdir -p "$STATE"
. /etc/home-alert.conf || exit 1
API="https://api.telegram.org/bot${TG_TOKEN}"
REPORT=/usr/local/sbin/home-report.sh
L() { if [ "$HOME_LANG" = ru ]; then printf '%s' "$1"; else printf '%s' "$2"; fi; }

send() {  # Telegram caps a message at 4096 characters
  curl -fsS -m 15 "$API/sendMessage" --data-urlencode "chat_id=${TG_CHAT}" --data-urlencode "text=${1:0:4000}" >/dev/null 2>&1
}

# the command menu next to the input field
jq -n --arg a "$(L "общая сводка" "overall summary")" --arg b "$(L "батарея подробно" "battery details")" \
  --arg c "$(L "нагрузка, память, диски" "load, memory, disks")" --arg d "$(L "контейнеры и сеть" "containers and network")" \
  --arg e "$(L "статистика блокировки рекламы" "ad-blocking statistics")" --arg f "$(L "проверить, заблокирован ли сайт" "is a site blocked")" \
  --arg g "$(L "последние бэкапы" "latest backups")" --arg h "$(L "недельный отчёт сейчас" "weekly report now")" \
  --arg i "$(L "лимит зарядки батареи" "battery charge limit")" --arg j "$(L "профиль охлаждения" "cooling profile")" \
  --arg k "$(L "включить ПК по сети" "wake the PC over the network")" --arg m "$(L "ПК выключен, спит или работает" "is the PC off, asleep or on")" \
  '{commands: [{command:"status",description:$a},{command:"battery",description:$b},{command:"system",description:$c},
  {command:"services",description:$d},{command:"ads",description:$e},{command:"check",description:$f},
  {command:"backup",description:$g},{command:"report",description:$h},{command:"charge",description:$i},
  {command:"fan",description:$j},{command:"wake",description:$k},{command:"pc",description:$m},{command:"help",description:"help"}]}' |
  curl -fsS -m 15 -H 'Content-Type: application/json' -d @- "$API/setMyCommands" >/dev/null 2>&1

report() { timeout "$1" "$REPORT" "${@:2}" </dev/null; }  # stdin closed so nothing eats the queued updates
control() { timeout "$1" /usr/local/sbin/home-control.sh "${@:2}" </dev/null; }

handle() {
  local cmd arg out
  read -r cmd arg <<<"$1"
  cmd=${cmd%%@*}; cmd=${cmd,,}
  case "$cmd" in
    /start|/help) out=$(report 10 help) ;;
    /status|/s) out=$(report 90 status) ;;
    /battery|/bat) out=$(report 10 battery) ;;
    /system) out=$(report 60 system) ;;
    /services) out=$(report 90 services) ;;
    /ads) out=$(report 60 ads) ;;
    /check) out=$(report 30 check "$arg") ;;
    /backup|/backups) out=$(report 10 backup) ;;
    /report|/weekly) out=$(report 120 weekly) ;;
    /charge) out=$(control 20 charge "$arg") ;;
    /fan) out=$(control 20 fan "$arg") ;;
    /wake) out=$(control 90 wake) ;;
    /pc) out=$(control 30 pc) ;;
    /*) out="$(L "Не знаю такую команду. Список: /help" "Unknown command. See /help")" ;;
    *) return ;;
  esac
  send "$out"
}

OFF=$(cat "$STATE/bot_offset" 2>/dev/null || echo 0)
while true; do
  R=$(curl -fsS -m 65 "$API/getUpdates" --data-urlencode "offset=$OFF" --data-urlencode "timeout=50" \
        --data-urlencode 'allowed_updates=["message"]' 2>/dev/null) || { sleep 10; continue; }
  while IFS=$'\t' read -r id chat text; do
    [ -n "$id" ] || continue
    OFF=$((id + 1)); echo "$OFF" > "$STATE/bot_offset"
    [ "$chat" = "$TG_CHAT" ] && [ -n "$text" ] && handle "$text"
  done < <(jq -r '.result[]? | [.update_id, (.message.chat.id // "" | tostring), (.message.text // "" | gsub("[\\t\\n\\r]"; " "))] | @tsv' <<<"$R" 2>/dev/null)
done
