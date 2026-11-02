# Setup order

Rough order that worked. Each step is small and can be checked before the next one.

## 1. Proxmox host

1. Install Proxmox VE on the laptop with a wired connection and a static address (example: `192.168.1.10`).
2. Switch to the no-subscription repository and update.
3. Make the lid and sleep harmless: set `HandleLidSwitch=ignore` (and the docked/external-power variants) in
   `/etc/systemd/logind.conf`, mask the sleep targets. Optional: `consoleblank=60` on the kernel command line so the
   screen turns off.
4. If the NIC is a USB adapter, see [notes.md](notes.md) before going on.
5. `bash host/install.sh`.

## 2. Containers

Two unprivileged Debian LXC containers, both `onboot: 1`, started in order (AdGuard first):

| CT | Role | Example address | Memory |
|---|---|---|---|
| 111 | AdGuard Home | 192.168.1.11 | 1 GB |
| 112 | monitor (Docker) | 192.168.1.12 | 2 GB |

For the monitor container enable `nesting=1` and `keyctl=1` so Docker runs inside it.

## 3. AdGuard Home

Install the official release into CT 111, finish the web wizard, then add the lists and settings from
`adguard/filters.yaml` in the web UI. Point the router's DHCP DNS at the container, and set a public AdGuard
DNS (`94.140.14.14`) as the secondary, so the network keeps working when the server is down.

## 4. Monitoring stack

Copy `stack/` to `/opt/stack` in CT 112 and run `docker compose up -d`.

- Caddy answers on port 80 and routes by host name: `status.home` → Uptime Kuma, `grafana.home` → Grafana,
  everything else → Homepage. Add the matching rewrites in AdGuard (see `adguard/filters.yaml`).
- Prometheus scrapes `node_exporter` on the host (port 9100). Install it with
  `apt install prometheus-node-exporter` and keep only the collectors you need.
- Grafana loads the dashboard from `grafana/provisioning/dashboards/server.json`.

In Uptime Kuma add monitors for: internet (ping `1.1.1.1`), router (ping), DNS (query through AdGuard),
Proxmox (HTTPS, ignore the self-signed certificate) and a **push** monitor for the power state. Copy the push URL to
`/etc/kuma-push-url` on the host; `kuma-power-push.timer` then reports every minute. Add a Telegram notification
and set it as default.

## 5. Telegram

1. Create a bot with @BotFather and send it any message from your account.
2. Put the token and your chat id into `/etc/home-alert.conf`.
3. `bash host/proxmox-telegram-notify.sh` sends Proxmox notifications to the same chat.
4. Optional: create a check on healthchecks.io (period 5 min, grace 10 min, Telegram integration) and write its ping
   URL to `/etc/healthchecks-url`. The watchdog pings it, so you also get an alert if the whole server goes dark,
   which nothing running on the server itself can report.

## 6. Backups

A weekly `vzdump` of all containers (Datacenter → Backup, Sunday 03:30, keep last 4, zstd). They land on the same disk
as the system, so copy them somewhere else if the data matters. The watchdog alerts when the newest dump is older than
9 days.
