#!/bin/bash
# Actions behind the Telegram commands that change something (home-report.sh only reads).
#   home-control.sh charge [percent] | fan [quiet|balanced|performance|apply] | wake
# Config: /etc/home-alert.conf (PC_MAC and PC_IP for wake), /etc/default/battery-limit, /etc/default/home-thermal
. /usr/local/sbin/home-report.sh   # L, tmax and the config; does nothing when sourced
LIMIT_CONF=/etc/default/battery-limit
THERMAL_CONF=/etc/default/home-thermal
TURBO=/sys/devices/system/cpu/intel_pstate/no_turbo

charge() {  # charge [percent]: show or set the charge limit (recharge starts 5 points below it)
  if [ -n "$1" ]; then
    if [[ $1 =~ ^[0-9]{2,3}$ ]] && [ "$1" -ge 50 ] && [ "$1" -le 100 ]; then
      printf 'CHARGE_MAX=%s\nCHARGE_MIN=%s\n' "$1" "$(( $1 - 5 ))" > "$LIMIT_CONF"
      CHARGE_MAX=$1; CHARGE_MIN=$(( $1 - 5 ))
      /usr/local/sbin/battery-limit.sh   # apply right away
    else
      L "Укажи число от 50 до 100, например /charge 80" "Give a number from 50 to 100, e.g. /charge 80"; echo; return
    fi
  fi
  echo "🎯 $(L "Лимит зарядки" "Charge limit"): ${CHARGE_MAX}% ($(L "подзарядка с" "recharge from") ${CHARGE_MIN}%)"
  battery_text | head -1
  echo "$(L "Изменить" "Change"): /charge 80"
}

fan_apply() {  # fan_apply quiet|balanced|performance: CPU governor, energy preference and turbo for all cores
  local gov epp nt c
  case "$1" in
    quiet) gov=powersave; epp=power; nt=1 ;;
    performance) gov=performance; epp=performance; nt=0 ;;
    *) gov=powersave; epp=balance_performance; nt=0 ;;
  esac
  for c in /sys/devices/system/cpu/cpu[0-9]*/cpufreq; do
    echo "$gov" > "$c/scaling_governor" 2>/dev/null
    [ -w "$c/energy_performance_preference" ] && echo "$epp" > "$c/energy_performance_preference" 2>/dev/null
  done
  [ -w "$TURBO" ] && echo "$nt" > "$TURBO"
}
fan() {  # fan [profile]: show or set the cooling profile
  local cur=balanced nt
  PROFILE=balanced; [ -r "$THERMAL_CONF" ] && . "$THERMAL_CONF"; cur=$PROFILE
  case "$1" in
    quiet|balanced|performance) fan_apply "$1"; printf 'PROFILE=%s\n' "$1" > "$THERMAL_CONF"; cur=$1 ;;
    apply) fan_apply "$cur"; return ;;
    "") ;;
    *) L "Профили: quiet, balanced, performance" "Profiles: quiet, balanced, performance"; echo; return ;;
  esac
  nt=$(cat $TURBO 2>/dev/null)
  echo "🌀 $(L Профиль Profile): $cur ($(L процессор CPU): $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor), $(L турбо turbo) $([ "$nt" = 0 ] && L вкл on || L выкл off))"
  echo "🌡 $(L Процессор CPU): $(tmax)°C"
  echo "/fan quiet — $(L "тихо, турбо выключен" "quiet, turbo off")"
  echo "/fan balanced — $(L "по умолчанию" "default")"
  echo "/fan performance — $(L "максимум производительности" "maximum performance")"
  echo "ℹ️ $(L "Обороты вентилятора этого ноутбука напрямую не читаются и не задаются: профиль меняет нагрев процессора, а значит и шум." "This laptop does not expose fan speed or control, so the profile changes CPU heat and with it the noise.")"
}

pc_state() {  # awake: answers ping | present: answers ARP only (asleep, or ping blocked) | absent: not on the network
  ip neigh flush to "$PC_IP" >/dev/null 2>&1
  if ping -c1 -W2 "$PC_IP" >/dev/null 2>&1; then echo awake; return; fi
  case "$(ip neigh show "$PC_IP" 2>/dev/null | awk '{print $NF}')" in
    FAILED|INCOMPLETE|"") echo absent ;;
    *) echo present ;;
  esac
}
pc_text() {
  case "$1" in
    awake) echo "🟢 $(L "ПК включён и отвечает на ping" "The PC is on and answers ping")" ;;
    present) echo "🟡 $(L "ПК в сети, но на ping не отвечает: спит (режим ожидания) или Windows блокирует ping" "The PC is on the network but does not answer ping: asleep (standby) or Windows blocks ping")" ;;
    *) echo "🔴 $(L "ПК не в сети: выключен, в гибернации или без Wi-Fi. По Wi-Fi из этого состояния не разбудить" "The PC is not on the network: off, hibernating or without Wi-Fi. It cannot be woken over Wi-Fi from that state")" ;;
  esac
}
pc() {  # /pc: is the PC off, asleep or on
  if [ -z "$PC_IP" ]; then L "Не задан PC_IP в /etc/home-alert.conf" "PC_IP is not set in /etc/home-alert.conf"; echo; return; fi
  pc_text "$(pc_state)"
}

wake() {  # send a Wake-on-LAN magic packet to PC_MAC, then watch PC_IP for 30 s
  local before now
  if [ -z "$PC_MAC" ]; then L "Не задан PC_MAC в /etc/home-alert.conf" "PC_MAC is not set in /etc/home-alert.conf"; echo; return; fi
  if [ -n "$PC_IP" ]; then
    before=$(pc_state)
    if [ "$before" = awake ]; then pc_text awake; return; fi
    [ "$before" = absent ] && echo "$(pc_text absent)"
  fi
  python3 - "$PC_MAC" "$PC_IP" <<'PY' || { L "Неверный PC_MAC" "Invalid PC_MAC"; echo; return; }
import socket, sys, time
mac = bytes.fromhex(sys.argv[1].replace(":", "").replace("-", ""))
assert len(mac) == 6
packet = b"\xff" * 6 + mac * 16
sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
ip = sys.argv[2]
targets = [("255.255.255.255", 9)]
if ip:
    targets += [(ip.rsplit(".", 1)[0] + ".255", 9), (ip.rsplit(".", 1)[0] + ".255", 7), (ip, 9)]
for _ in range(3):
    for target in targets:
        sock.sendto(packet, target)
    time.sleep(1)
PY
  echo "📡 $(L "Сигнал включения отправлен на" "Magic packet sent to") $PC_MAC"
  [ -n "$PC_IP" ] || return
  for _ in $(seq 6); do
    sleep 4
    now=$(pc_state)
    if [ "$now" = awake ]; then echo "✅ $(L "ПК проснулся и отвечает" "The PC woke up and answers")"; return; fi
    if [ "$before" = absent ] && [ "$now" = present ]; then echo "✅ $(L "ПК появился в сети (ping Windows блокирует)" "The PC appeared on the network (Windows blocks ping)")"; return; fi
  done
  pc_text "$now"
  [ "$now" = present ] && echo "$(L "Не понять, проснулся ли он: разреши в Windows ping из локальной сети (см. памятку)" "Cannot tell whether it woke up: allow ping from the local network in Windows (see the notes)")"
}

[[ ${BASH_SOURCE[0]} != "$0" ]] && return 0
case "$1" in
  charge) charge "$2" ;;
  fan) fan "$2" ;;
  wake) wake ;;
  pc) pc ;;
  *) echo "usage: $0 charge [percent] | fan [quiet|balanced|performance|apply] | wake | pc" >&2; exit 1 ;;
esac
