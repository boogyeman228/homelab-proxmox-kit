# Alerts

Two sources send to Telegram.

## home-watchdog (every 5 minutes, runs on the Proxmox host)

A message goes out when a check turns bad, a reminder every 6 hours while it stays bad, and a "Recovered"
message when it clears. State is stored in `/var/lib/home-watchdog/`. A state change is only recorded after
Telegram accepted the message, so alerts raised during an internet outage arrive once it is back.

| Check | Bad when |
|---|---|
| Mains power | host runs on battery |
| Battery | on battery and charge ≤ 30% |
| Root disk | ≥ 85% used |
| Container storage (`local-lvm`) | ≥ 85% used |
| Monitor container disk | ≥ 85% used |
| Temperature | any thermal zone ≥ 85 °C |
| Memory | less than 300 MB available |
| Containers | AdGuard or monitor container not running |
| Docker services | any of the five services missing or unhealthy |
| Uptime Kuma, Grafana | no HTTP answer through Caddy |
| Prometheus | host target not `up` |
| DNS | AdGuard does not answer a query |
| Tailscale | backend state is not `Running` |
| Backups | newest dump older than 9 days |
| Reboot | boot id changed since the last run |

## Uptime Kuma

Internet (ping), router (ping), DNS through AdGuard, Proxmox web UI and the power push monitor. The power monitor
needs two consecutive "down" pushes (retries = 1), so a battery alert arrives after about two minutes.

## Proxmox notifications

Failed backups and other Proxmox events go through the `telegram` webhook target
(`host/proxmox-telegram-notify.sh`). Without it they would only be mailed to root, which nobody reads on a
box without a mail relay.

## Known gaps

- If the router loses power it takes the internet with it, so a "running on battery" alert cannot leave the house
  unless the router is on a UPS too. You still get the "Recovered" and "rebooted" messages afterwards.
- Anything running on the server cannot report that the server itself is dead. That is what the optional
  external ping (`/etc/healthchecks-url`) is for.
