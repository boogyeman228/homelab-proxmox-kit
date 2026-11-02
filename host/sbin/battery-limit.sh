#!/bin/sh
# Charge limit for a laptop that stays on mains all the time. Charges up to CHARGE_MAX, then switches the
# firmware's conservation mode on (no more charging) and charges again only when the level falls to
# CHARGE_MIN. The hysteresis keeps the battery between the two values instead of at 100%.
# Config: /etc/default/battery-limit (CHARGE_MAX, CHARGE_MIN). Runs every minute from battery-limit.timer.
CHARGE_MAX=80
CHARGE_MIN=75
[ -r /etc/default/battery-limit ] && . /etc/default/battery-limit
CM=/sys/bus/platform/drivers/ideapad_acpi/VPC2004:00/conservation_mode
[ -w "$CM" ] || exit 0
cap=$(cat /sys/class/power_supply/BAT0/capacity)
ac=$(cat /sys/class/power_supply/ADP0/online)
cur=$(cat "$CM")
[ "$ac" = 1 ] || exit 0   # on battery: leave things as they are, the next run after mains is back decides
if [ "$cap" -ge "$CHARGE_MAX" ] && [ "$cur" != 1 ]; then
  echo 1 > "$CM"; logger -t battery-limit "${cap}% >= ${CHARGE_MAX}%: charging stopped"
elif [ "$cap" -le "$CHARGE_MIN" ] && [ "$cur" != 0 ]; then
  echo 0 > "$CM"; logger -t battery-limit "${cap}% <= ${CHARGE_MIN}%: charging started"
fi
