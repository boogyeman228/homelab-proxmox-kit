#!/bin/sh
# Every minute: tell Uptime Kuma whether the server runs on mains or battery.
# Push URL lives in /etc/kuma-push-url (one line). No file -> do nothing.
[ -s /etc/kuma-push-url ] || exit 0
URL=$(head -n1 /etc/kuma-push-url)
AC=$(cat /sys/class/power_supply/ADP0/online 2>/dev/null)
CAP=$(cat /sys/class/power_supply/BAT0/capacity 2>/dev/null)
if [ "$AC" = "1" ]; then
  curl -fsS -m 10 -G "$URL" --data-urlencode "status=up" --data-urlencode "msg=AC ok, battery ${CAP}%" >/dev/null
else
  curl -fsS -m 10 -G "$URL" --data-urlencode "status=down" --data-urlencode "msg=ON BATTERY ${CAP}% - power outage?" >/dev/null
fi
