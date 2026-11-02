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
| Telegram bot | `home-bot.service` is not running |

## Reports and commands

- **Daily report** (Mon-Sat 09:00): problems or "all good", power, uptime, CPU temperature, disk, ads blocked
  yesterday, age of the last backup.
- **Weekly report** (Sunday 09:00): everything above plus battery health and cycles, memory, all disks, ads blocked
  in 7 days with the top blocked domains, backup list, pending Proxmox updates, Tailscale devices.
- **Commands** you can send the bot at any time: `/status`, `/battery`, `/system`, `/services`, `/ads`,
  `/check <site>` (blocked or not, by which rule and list), `/backup`, `/report`, `/help`.
- **Commands that change something:** `/charge 80` sets the battery charge limit (recharge starts 5 points below),
  `/fan quiet|balanced|performance` sets the CPU profile, `/wake` sends a Wake-on-LAN packet.

## Charge limit, cooling, Wake-on-LAN

- **Charge limit** (`battery-limit.timer`, every minute): the firmware only knows "conservation mode" (hold at about
  60%) or full charge, so the script switches it by hysteresis: charge until `CHARGE_MAX` (default 80), then stop, charge
  again when the level falls to `CHARGE_MIN` (default 75). While on battery nothing is changed.
- **Cooling:** this class of laptop does not expose fan speed or control to Linux (the embedded controller returns
  unrelated values), so `/fan` changes the CPU governor, energy preference and turbo instead. That lowers heat and
  therefore noise. The profile is saved in `/etc/default/home-thermal` and applied at boot.
- **Wake-on-LAN:** put `PC_MAC` (and `PC_IP` for the confirmation ping) into `/etc/home-alert.conf`. The PC must allow
  waking on a magic packet (BIOS/UEFI and the network adapter's power settings). Over Wi-Fi this works only from sleep /
  modern standby, not from a full shutdown; wired Ethernet also works from shutdown if the BIOS allows it.
- **PC state (`/pc`, also used by `/wake`):** 🟢 answers ping (awake), 🟡 answers ARP only (asleep, or ping blocked),
  🔴 not on the network (off or hibernating). A sleeping Wi-Fi PC still answers ARP, so telling "asleep" from "awake"
  needs ping to be allowed. Windows blocks it by default; allow it for the home network only, in an admin PowerShell:
  `New-NetFirewallRule -DisplayName "Ping from home LAN" -Protocol ICMPv4 -IcmpType 8 -RemoteAddress 192.168.1.0/24 -Action Allow`

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
