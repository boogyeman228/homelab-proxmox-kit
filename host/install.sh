#!/bin/bash
# Installs the host-side scripts and systemd units on the Proxmox host. Run as root from the repo root:
#   bash host/install.sh
# Safe to run again. Existing config files are never overwritten.
set -e
cd "$(dirname "$0")"

install -m 755 bin/battery /usr/local/bin/battery
install -m 755 sbin/*.sh /usr/local/sbin/
install -m 644 systemd/* /etc/systemd/system/
install -m 644 sysctl/*.conf /etc/sysctl.d/
sysctl --system >/dev/null

[ -e /etc/home-alert.conf ] || { install -m 600 etc/home-alert.conf.example /etc/home-alert.conf; echo "-> edit /etc/home-alert.conf (Telegram token and chat id)"; }
[ -e /etc/default/usb-lan-fix ] || echo "-> USB NIC watchdog not enabled. If the host uses a USB LAN adapter: copy etc/usb-lan-fix.example to /etc/default/usb-lan-fix, edit it, then 'systemctl enable --now usb-lan-fix'"

systemctl daemon-reload
systemctl enable --now battery-guard.timer home-watchdog.timer home-digest.timer home-daily.timer home-bot.service
systemctl try-restart home-bot.service   # pick up a newer script on re-runs
# the Kuma push monitor stays idle until /etc/kuma-push-url exists
systemctl enable --now kuma-power-push.timer
[ -e /etc/default/usb-lan-fix ] && systemctl enable --now usb-lan-fix.service
echo "Installed. Check: systemctl list-timers | grep -E 'home-|battery|kuma'"
