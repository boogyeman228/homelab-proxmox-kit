# homelab-proxmox-kit

Configs and scripts for a small always-on home server: an old laptop running Proxmox VE with
network-wide ad blocking (AdGuard Home), a monitoring stack (Uptime Kuma, Prometheus, Grafana)
and Telegram alerts that do not depend on any single component.

It was built for a laptop on a residential connection behind CGNAT, so nothing here needs
inbound ports. Remote access goes through Tailscale.

## What you get

| Piece | Where | What it does |
|---|---|---|
| AdGuard Home (LXC) | `adguard/` | DNS ad/tracker/malware blocking, optional adult, gambling and scam lists, short local names |
| Monitoring stack (LXC + Docker) | `stack/` | Uptime Kuma, Prometheus, Grafana (provisioned dashboard), Homepage start page, Caddy for `*.home` names |
| Watchdog | `host/sbin/home-watchdog.sh` | Checks host and stack every 5 minutes, sends Telegram alerts on state changes only |
| Weekly digest | `host/sbin/home-digest.sh` | Sunday summary: uptime, power, disk, last backup, pending updates |
| Power reporting | `host/sbin/kuma-power-push.sh` | Tells an Uptime Kuma push monitor whether the host is on mains or battery |
| Battery guard | `host/sbin/battery-guard.sh`, `host/bin/battery` | Clean shutdown below 10% on battery, `battery` status command |
| USB NIC watchdog | `host/sbin/usb-lan-fix.sh` | Re-attaches a USB Ethernet adapter to the bridge when it drops |
| Proxmox notifications | `host/proxmox-telegram-notify.sh` | Sends Proxmox events (failed backups etc.) to Telegram |

```
 router ──┬── Proxmox host (.10)  ── home-watchdog, digest, battery guard, node_exporter
          ├── CT adguard (.11)     ── AdGuard Home
          └── CT monitor (.12)     ── Docker: Caddy, Homepage, Uptime Kuma, Prometheus, Grafana
 Telegram ◄── watchdog (direct), Uptime Kuma, Proxmox notifications
```

The watchdog talks to Telegram on its own on purpose: if Uptime Kuma or the monitor container
dies, you still hear about it.

## Quick start

See [docs/setup.md](docs/setup.md) for the full order. The short version, on the Proxmox host:

```bash
git clone <this repo> && cd homelab-proxmox-kit
bash host/install.sh                    # scripts, systemd units, sysctl tuning
nano /etc/home-alert.conf               # Telegram bot token + chat id
bash host/proxmox-telegram-notify.sh    # route Proxmox notifications to Telegram
```

The monitoring stack goes into the `monitor` container: copy `stack/` to `/opt/stack` and run
`docker compose up -d`.

## Alerts

[docs/alerts.md](docs/alerts.md) lists every check and its threshold.

## Notes

- Addresses (`192.168.1.x`) and container IDs (`111`, `112`) are examples. The watchdog reads them
  from `/etc/home-alert.conf`; the `stack/` and `adguard/` files need a search and replace.
- Hardware quirks (USB NIC, battery conservation mode, CGNAT and Tailscale) are in
  [docs/notes.md](docs/notes.md).
- No secrets live in this repo. Tokens go to `/etc/home-alert.conf` (mode 600), which is git-ignored here.

## License

MIT
