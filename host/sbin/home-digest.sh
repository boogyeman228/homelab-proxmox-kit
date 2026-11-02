#!/bin/bash
# Sends a status report to Telegram: home-digest.sh daily|weekly (default weekly). Texts come from home-report.sh.
# Config: /etc/home-alert.conf
. /etc/home-alert.conf || exit 1
MSG=$(/usr/local/sbin/home-report.sh "${1:-weekly}") && [ -n "$MSG" ] || exit 1
curl -fsS -m 15 "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
  --data-urlencode "chat_id=${TG_CHAT}" --data-urlencode "text=${MSG:0:4000}" >/dev/null
