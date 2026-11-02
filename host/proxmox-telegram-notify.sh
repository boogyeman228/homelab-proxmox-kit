#!/bin/bash
# Routes Proxmox notifications (failed backups, updates, ...) to Telegram through a webhook target.
# Needs /etc/home-alert.conf (TG_TOKEN, TG_CHAT). Run once as root on the Proxmox host.
set -e
. /etc/home-alert.conf
b64() { printf '%s' "$1" | base64 -w0; }
BODY=$(printf '{"chat_id":"%s","text":"Proxmox: {{ escape title }}\n{{ escape message }}"}' "$TG_CHAT")
pvesh create /cluster/notifications/endpoints/webhook --name telegram --method post \
  --url 'https://api.telegram.org/bot{{ secrets.token }}/sendMessage' \
  --header "name=Content-Type,value=$(b64 'application/json')" \
  --body "$(b64 "$BODY")" \
  --secret "name=token,value=$(b64 "$TG_TOKEN")"
pvesh set /cluster/notifications/matchers/default-matcher --target mail-to-root --target telegram
pvesh create /cluster/notifications/targets/telegram/test
echo "Test message sent."
