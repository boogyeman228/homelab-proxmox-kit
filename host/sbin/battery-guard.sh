#!/bin/sh
# Clean shutdown when running on battery and charge drops below 10% (power outage)
CAP=$(cat /sys/class/power_supply/BAT0/capacity)
ST=$(cat /sys/class/power_supply/BAT0/status)
if [ "$ST" = "Discharging" ] && [ "$CAP" -lt 10 ]; then
  logger -t battery-guard "battery at ${CAP}%, shutting down"
  shutdown -h now "Battery low (${CAP}%)"
fi
