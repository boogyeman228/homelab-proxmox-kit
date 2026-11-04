# Notes and quirks

## USB Ethernet adapter

A laptop has one Wi-Fi card and no spare NIC, so a USB 3 gigabit adapter (Realtek RTL8153) carries all traffic via
the `vmbr0` bridge.

- The Proxmox installer may bridge the Wi-Fi interface instead. Move `bridge-ports` to the USB NIC in
  `/etc/network/interfaces`.
- USB NICs sometimes do not show up after boot or vanish after a power glitch. `usb-lan-fix` checks every 15 seconds,
  resets the xhci controller (up to three tries) and runs `ifreload -a` if the NIC is not on the bridge. Configure
  it in `/etc/default/usb-lan-fix` (`etc/usb-lan-fix.example`).
- Offload tweak used on the NIC (in `interfaces`, `post-up`):
  `ethtool -K <nic> rx-udp-gro-forwarding on rx-gro-list off`, which makes Tailscale exit-node traffic faster.

## Battery

Lenovo IdeaPad laptops expose `conservation_mode` (`/sys/bus/platform/drivers/ideapad_acpi/VPC2004:00/`). With it
on, the battery sits around 60%, which is kinder to a laptop that stays plugged in for years. `battery` prints
charge, health, cycles and whether conservation mode is on. `battery-guard` shuts the machine down cleanly under
10% on battery.

## Network tuning

`host/sysctl/98-net-speed.conf` enables BBR with `fq`. `99-tailscale.conf` turns on IP forwarding for the Tailscale
subnet-router / exit-node role.

## CGNAT and Tailscale

If the ISP puts you behind carrier-grade NAT, port forwarding is impossible. Tailscale works anyway; outside the
house traffic may be relayed (DERP), which is slower, especially when using the server as an exit node.

Advertise the AdGuard address as a route and set it as the tailnet DNS server (with "override local DNS") so
phones keep ad blocking away from home. Disable key expiry for the server in the Tailscale admin console.

## Updates

Containers get unattended security upgrades. The Docker images tagged `latest` (Kuma, Grafana, Homepage, Apprise) are pulled by a weekly job
inside the monitor container. Proxmox itself is updated by hand about once a month.
Speedtest Tracker and Memos are pinned to a version on purpose: bump the tag by hand after reading the release notes.

## Ceph on one node

Proxmox offers to install Ceph, but on a single laptop with one disk it does nothing useful: Ceph needs at least
three nodes (or three OSD disks) and a disk of its own for each OSD. Installed anyway, the monitor and manager
take about 400 MB of RAM, and the default `ceph-*` enterprise repository breaks `apt update` without a
subscription. Use `local-lvm` for disks and a USB drive or NAS for backups instead.
